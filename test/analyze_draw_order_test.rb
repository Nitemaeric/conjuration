# DrawOrderAnalyzer (tools/analyze_draw_order.rb) — the offline over/under split
# for a dump written by Camera#dump_draw_order. The tool's CLI is guarded, so
# preloading it only defines the module; these exercise its pure functions. This
# ports the isometric demo's planted-culprit test: one primitive is arranged to
# overlap the target from later in flush order (the occluder), another from
# earlier (context), and a third off to the side (a non-overlap that must be
# ignored).

def planted_dump
  [
    "# synthetic draw-order dump",
    "camera name=main x=0 y=0 zoom=1 w=1280 h=720",
    "view x=0 y=0 w=1280 h=720",
    "prim idx=0 z=8 em=0 x=100 y=100 w=100 h=100 ax=0.5 ay=0 path=sprites/dirt.png tag=cube_a",
    "prim idx=1 z=8 em=1 x=120 y=140 w=40 h=100 ax=0.5 ay=0 path=sprites/knight.png tag=knight",
    "prim idx=2 z=9 em=2 x=130 y=150 w=100 h=120 ax=0.5 ay=0.5 path=sprites/tree.png tag=culprit",
    "prim idx=3 z=7 em=3 x=1000 y=100 w=10 h=10 ax=0 ay=0 path=sprites/far.png tag=faraway"
  ].join("\n")
end

def test_analyzer_parses_header_and_prims(args, assert)
  parsed = DrawOrderAnalyzer.parse(planted_dump)

  assert.equal!(parsed[:header]["camera"]["name"], "main", "camera header parsed")
  assert.equal!(parsed[:header]["view"]["w"], "1280", "view header parsed")
  assert.equal!(parsed[:prims].length, 4, "every prim line collected in order")
  assert.equal!(parsed[:prims][1]["tag"], "knight", "prim fields keyed by token name")
end

def test_analyzer_splits_over_and_under_a_tagged_target(args, assert)
  parsed = DrawOrderAnalyzer.parse(planted_dump)
  tgt = DrawOrderAnalyzer.target(parsed[:prims], tag: "knight")
  result = DrawOrderAnalyzer.analyze(parsed[:prims], tgt)

  over = result[:over].map { |e| e[:prim]["tag"] }
  under = result[:under].map { |e| e[:prim]["tag"] }

  assert.equal!(over, ["culprit"], "the planted culprit is the sole prim drawn over the target")
  assert.equal!(under, ["cube_a"], "the target's own cell sits under it; the faraway prim never overlaps")
end

def test_analyzer_over_entries_carry_the_overlap_box(args, assert)
  parsed = DrawOrderAnalyzer.parse(planted_dump)
  tgt = DrawOrderAnalyzer.target(parsed[:prims], tag: "knight")
  result = DrawOrderAnalyzer.analyze(parsed[:prims], tgt)

  o = result[:over].first[:overlap]
  assert.close!(o[:w], 40, "overlap width of the culprit over the knight")
  assert.close!(o[:h], 70, "overlap height of the culprit over the knight")
end

def test_analyzer_returns_nil_for_a_missing_tag(args, assert)
  parsed = DrawOrderAnalyzer.parse(planted_dump)
  assert.nil!(DrawOrderAnalyzer.target(parsed[:prims], tag: "ghost"), "an unknown tag resolves to no target")
end

def test_analyzer_rect_target_reports_overlaps_as_over(args, assert)
  parsed = DrawOrderAnalyzer.parse([
    "prim idx=0 z=0 em=0 x=0 y=0 w=100 h=100 ax=0 ay=0 path=p tag=a",
    "prim idx=1 z=0 em=1 x=500 y=500 w=10 h=10 ax=0 ay=0 path=p tag=b"
  ].join("\n"))
  tgt = DrawOrderAnalyzer.target(parsed[:prims], box: { l: 10, b: 10, r: 50, t: 50 })
  result = DrawOrderAnalyzer.analyze(parsed[:prims], tgt)

  assert.equal!(result[:over].map { |e| e[:prim]["tag"] }, ["a"], "the overlapping prim is reported over the query rect")
  assert.equal!(result[:under].length, 0, "a bare rect query has no under bucket")
end

def test_analyzer_report_lines_render_the_sections(args, assert)
  parsed = DrawOrderAnalyzer.parse(planted_dump)
  tgt = DrawOrderAnalyzer.target(parsed[:prims], tag: "knight")
  text = DrawOrderAnalyzer.report_lines(parsed, tgt).join("\n")

  assert.true!(text.include?("drawn OVER the target (1)"), "the over section names its count")
  assert.true!(text.include?("culprit"), "the culprit is listed by tag")
  assert.true!(text.include?("drawn UNDER the target (1)"), "the under section names its count")
end
