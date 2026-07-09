#!/usr/bin/env ruby
# Analyzes an iso_draw_dump.txt captured in the isometric demo (freeze the walk
# with K, press P; the file lands in DragonRuby's sandboxed write root — the
# game directory in dev builds, the OS data dir in production builds).
#
# Reports the knight's screen rect and every primitive flushed AFTER him whose
# rect intersects his — i.e. everything DragonRuby composites over the knight —
# with cell/level identification and the exact overlap boxes.
#
# Usage: ruby demo/tools/analyze_iso_dump.rb iso_draw_dump.txt

path = ARGV[0]
abort "usage: ruby demo/tools/analyze_iso_dump.rb iso_draw_dump.txt" unless path && File.exist?(path)

header = {}
prims = []

File.foreach(path) do |line|
  line = line.strip
  next if line.empty? || line.start_with?("#")

  kind, *tokens = line.split(/\s+/)
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

abort "no prim lines found — is this an iso draw dump?" if prims.empty?

def f(fields, key, default = 0.0)
  v = fields[key]
  v.nil? || v.empty? || v == "nil" ? default : v.to_f
end

# Viewport-space rect, y-up: the anchor point is (x, y); the drawn rect spans
# [x - ax*w, x + (1-ax)*w] x [y - ay*h, y + (1-ay)*h].
def rect(p)
  w = f(p, "w")
  h = f(p, "h")
  left = f(p, "x") - f(p, "ax") * w
  bottom = f(p, "y") - f(p, "ay") * h
  { l: left, b: bottom, r: left + w, t: bottom + h }
end

def overlap(a, b)
  l = [a[:l], b[:l]].max
  r = [a[:r], b[:r]].min
  bo = [a[:b], b[:b]].max
  t = [a[:t], b[:t]].min
  return nil if l >= r || bo >= t

  { l: l, b: bo, r: r, t: t, w: r - l, h: t - bo }
end

def label(p)
  dbg = p["dbg"]
  dbg && !dbg.empty? && dbg != "nil" ? dbg : File.basename(p["path"].to_s)
end

knight = prims.find { |p| p["dbg"] == "knight" } || prims.find { |p| p["path"].to_s.include?("knight") }
abort "no knight primitive in the dump" unless knight

knight_idx = knight["idx"].to_i
krect = rect(knight)
feet_y = f(knight, "y") - f(knight, "ay") * f(knight, "h")

puts "dump: #{prims.length} primitives"
header.each { |kind, fields| puts "#{kind}: #{fields.map { |k, v| "#{k}=#{v}" }.join(" ")}" }
puts
puts format("knight: flush idx=%d z=%s rect l=%.1f b=%.1f r=%.1f t=%.1f (feet y=%.1f)",
            knight_idx, knight["z"], krect[:l], krect[:b], krect[:r], krect[:t], feet_y)
puts

over = []
under = []
prims.each do |p|
  next if p.equal?(knight)

  o = overlap(krect, rect(p))
  next unless o

  (p["idx"].to_i > knight_idx ? over : under) << [p, o]
end

puts "== drawn OVER the knight (#{over.length}) — these are the clip suspects =="
over.sort_by { |(_, o)| -o[:w] * o[:h] }.each do |(p, o)|
  reach = o[:t] - feet_y
  puts format("  idx=%-4s z=%-4s %-18s overlap l=%.1f b=%.1f w=%.1f h=%.1f — reaches %.1f above the feet line",
              p["idx"], p["z"], label(p), o[:l], o[:b], o[:w], o[:h], reach)
end
puts "  (none)" if over.empty?

puts
puts "== drawn UNDER the knight (#{under.length}) — context, expected: his own cell =="
under.each do |(p, o)|
  puts format("  idx=%-4s z=%-4s %-18s overlap w=%.1f h=%.1f", p["idx"], p["z"], label(p), o[:w], o[:h])
end
puts "  (none)" if under.empty?
