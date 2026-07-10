#!/usr/bin/env ruby
# Draw-order inspector — offline analyzer for a dump written by
# Conjuration::Camera#dump_draw_order (roadmap H3, promoted from the isometric
# demo's knight-specific script).
#
# Given a dump and a target — either a tagged primitive (`--tag NAME`, matched
# against the `dbg:` convention key) or an explicit viewport rect
# (`--rect L,B,R,T`) — it reports every primitive whose rect overlaps the
# target, split into those drawn OVER it (later in flush order — the occlusion
# suspects) and those drawn UNDER it (earlier — context), each with the exact
# overlap box.
#
# Usage:
#   ruby tools/analyze_draw_order.rb DUMP --tag knight
#   ruby tools/analyze_draw_order.rb DUMP --rect 100,50,260,300
#
# The module holds the pure logic (parsing, geometry, the over/under split) so
# it is unit-testable; the CLI at the bottom only runs when invoked as a script.
# No regexen — plain string splitting, so the same code runs under CRuby and
# DragonRuby's mruby.
module DrawOrderAnalyzer
  extend self

  # Parse dump text into { header: { kind => {k=>v} }, prims: [ {k=>v}, ... ] }.
  # Header lines (camera, view) key by their leading word; `prim` lines collect
  # into the ordered primitive list. Comments (#) and blanks are skipped.
  def parse(text)
    header = {}
    prims = []

    text.split("\n").each do |raw|
      line = raw.strip
      next if line.empty? || line.start_with?("#")

      tokens = line.split(" ")
      kind = tokens.shift
      fields = {}
      tokens.each do |token|
        key, value = token.split("=", 2)
        fields[key] = value
      end

      if kind == "prim"
        prims << fields
      else
        header[kind] = fields
      end
    end

    { header: header, prims: prims }
  end

  def num(fields, key, default = 0.0)
    v = fields[key]
    v.nil? || v.empty? || v == "nil" ? default : v.to_f
  end

  # Viewport-space rect, y-up: the anchor point is (x, y); the drawn rect spans
  # [x - ax*w, x + (1-ax)*w] x [y - ay*h, y + (1-ay)*h].
  def rect(p)
    w = num(p, "w")
    h = num(p, "h")
    left = num(p, "x") - num(p, "ax") * w
    bottom = num(p, "y") - num(p, "ay") * h
    { l: left, b: bottom, r: left + w, t: bottom + h }
  end

  def overlap(a, b)
    l = a[:l] > b[:l] ? a[:l] : b[:l]
    r = a[:r] < b[:r] ? a[:r] : b[:r]
    bo = a[:b] > b[:b] ? a[:b] : b[:b]
    t = a[:t] < b[:t] ? a[:t] : b[:t]
    return nil if l >= r || bo >= t

    { l: l, b: bo, r: r, t: t, w: r - l, h: t - bo }
  end

  def label(p)
    tag = p["tag"]
    tag && !tag.empty? && tag != "nil" ? tag : p["path"].to_s.split("/").last
  end

  # Resolve the target from options: a tagged primitive (giving a rect AND its
  # flush index, so over/under is by draw order) or an explicit rect (index -1,
  # so every overlap counts as drawn over the queried region). Returns
  # { rect:, idx:, prim: } or nil when a named tag is not found.
  def target(prims, tag: nil, box: nil)
    if tag
      prim = prims.find { |p| p["tag"] == tag }
      return nil unless prim

      { rect: rect(prim), idx: prim["idx"].to_i, prim: prim }
    else
      { rect: box, idx: -1, prim: nil }
    end
  end

  # Split every overlapping primitive into over/under the target by flush index.
  # Each entry is { prim:, overlap: }. Over is sorted by overlap area, largest
  # first — the biggest occluders lead.
  def analyze(prims, tgt)
    over = []
    under = []

    prims.each do |p|
      next if tgt[:prim] && p.equal?(tgt[:prim])

      o = overlap(tgt[:rect], rect(p))
      next unless o

      entry = { prim: p, overlap: o }
      (p["idx"].to_i > tgt[:idx] ? over : under) << entry
    end

    over = over.sort_by { |e| -(e[:overlap][:w] * e[:overlap][:h]) }
    { over: over, under: under }
  end

  def report_lines(parsed, tgt)
    result = analyze(parsed[:prims], tgt)
    tr = tgt[:rect]
    lines = []

    lines << "dump: #{parsed[:prims].length} primitives"
    parsed[:header].each do |kind, fields|
      lines << "#{kind}: #{fields.map { |k, v| "#{k}=#{v}" }.join(" ")}"
    end
    lines << ""

    if tgt[:prim]
      lines << format("target: %s flush idx=%d z=%s rect l=%.1f b=%.1f r=%.1f t=%.1f",
                      label(tgt[:prim]), tgt[:idx], tgt[:prim]["z"], tr[:l], tr[:b], tr[:r], tr[:t])
    else
      lines << format("target: rect l=%.1f b=%.1f r=%.1f t=%.1f (bare query rect — all overlaps count as over)",
                      tr[:l], tr[:b], tr[:r], tr[:t])
    end
    lines << ""

    lines << "== drawn OVER the target (#{result[:over].length}) — occlusion suspects =="
    result[:over].each do |e|
      p = e[:prim]
      o = e[:overlap]
      reach = o[:t] - tr[:b]
      lines << format("  idx=%-4s z=%-4s %-18s overlap l=%.1f b=%.1f w=%.1f h=%.1f — reaches %.1f above the target's bottom",
                      p["idx"], p["z"], label(p), o[:l], o[:b], o[:w], o[:h], reach)
    end
    lines << "  (none)" if result[:over].empty?
    lines << ""

    lines << "== drawn UNDER the target (#{result[:under].length}) — context =="
    result[:under].each do |e|
      p = e[:prim]
      o = e[:overlap]
      lines << format("  idx=%-4s z=%-4s %-18s overlap w=%.1f h=%.1f", p["idx"], p["z"], label(p), o[:w], o[:h])
    end
    lines << "  (none)" if result[:under].empty?

    lines
  end
end

if $PROGRAM_NAME == __FILE__
  path = ARGV[0]
  abort "usage: ruby tools/analyze_draw_order.rb DUMP [--tag NAME | --rect L,B,R,T]" unless path && File.exist?(path)

  tag = nil
  box = nil
  i = 1
  while i < ARGV.length
    case ARGV[i]
    when "--tag"
      tag = ARGV[i + 1]
      i += 2
    when "--rect"
      l, b, r, t = ARGV[i + 1].to_s.split(",").map(&:to_f)
      box = { l: l, b: b, r: r, t: t }
      i += 2
    else
      abort "unknown option: #{ARGV[i]}"
    end
  end

  abort "give a target: --tag NAME or --rect L,B,R,T" unless tag || box

  parsed = DrawOrderAnalyzer.parse(File.read(path))
  abort "no prim lines found — is this a draw-order dump?" if parsed[:prims].empty?

  tgt = DrawOrderAnalyzer.target(parsed[:prims], tag: tag, box: box)
  abort "no primitive tagged #{tag.inspect} in the dump" if tag && tgt.nil?

  puts DrawOrderAnalyzer.report_lines(parsed, tgt).join("\n")
end
