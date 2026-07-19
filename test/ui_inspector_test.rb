# UI tree inspector (roadmap H2): read-only debug overlay over the mounted node
# tree. These tests exercise the computed annotations — size provenance per axis,
# nil-geometry detection, overflow spill, and deepest-node-at-point hit
# resolution — plus the debug gate, without inspecting pixels.

Inspector = Conjuration::UI::Inspector

def inspector_root(&block)
  Conjuration::UI.build({ x: 0, y: 0, w: 400, h: 400 }, id: :root, &block)
end

# --- Size provenance per axis -------------------------------------------------

def test_provenance_explicit_on_authored_sizes(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :box) do
      node({ w: 100, h: 50, primitive_marker: :solid }, id: :leaf)
    end
  end

  provenance = Inspector.annotate(ui.find(:leaf))[:provenance]
  assert.equal!(provenance[:w], :explicit, "authored width is explicit")
  assert.equal!(provenance[:h], :explicit, "authored height is explicit")
end

def test_provenance_grow_on_the_parents_main_axis(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 400, h: 100 }, id: :bar, direction: :row) do
      node({ h: 50 }, id: :filler, grow: 1)
    end
  end

  filler = ui.find(:filler)
  provenance = Inspector.annotate(filler)[:provenance]

  assert.equal!(filler.object.w, 400, "grow distributed the whole row width to the filler")
  assert.equal!(provenance[:w], :grow, "the grown main axis is grow-provenance")
  assert.equal!(provenance[:h], :explicit, "the authored cross-axis size stays explicit")
end

def test_provenance_auto_on_content_sized_container(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 700, anchor_x: 0, anchor_y: 1 }, id: :auto, direction: :column) do
      node({ w: 120, h: 40, primitive_marker: :solid }, id: :child)
    end
  end

  auto = ui.find(:auto)
  provenance = Inspector.annotate(auto)[:provenance]

  assert.equal!([auto.object.w, auto.object.h], [120, 40], "auto-sized from its child")
  assert.equal!(provenance[:w], :auto, "content-derived width is auto")
  assert.equal!(provenance[:h], :auto, "content-derived height is auto")
end

def test_provenance_auto_for_text_node(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :box) do
      node({ text: "hello" }, id: :label)
    end
  end

  provenance = Inspector.annotate(ui.find(:label))[:provenance]
  assert.equal!(provenance[:w], :auto, "text width derives from the measured string")
  assert.equal!(provenance[:h], :auto, "text height derives from the measured string")
end

def test_provenance_max_clamped_flag(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 700, anchor_x: 0, anchor_y: 1 }, id: :box, direction: :row, max_w: 100) do
      node({ w: 150, h: 40, primitive_marker: :solid }, id: :child)
    end
  end

  box = ui.find(:box)
  annotation = Inspector.annotate(box)

  assert.equal!(box.object.w, 100, "auto width of 150 clamps to max_w 100")
  assert.equal!(annotation[:provenance][:w], :auto, "the size source is still content-derived")
  assert.true!(annotation[:provenance][:w_max_clamped], "the width axis reports it was max-clamped")
  assert.false!(annotation[:provenance][:h_max_clamped], "the uncapped height axis is not clamped")
end

# --- Nil geometry (the loud case) ---------------------------------------------

def test_unresolved_geometry_detection(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 400, anchor_x: 0, anchor_y: 1 }, id: :dialogue, wrap: true) do
      node({ w: 100, h: 50, primitive_marker: :solid }, id: :box)
    end
  end

  dialogue = ui.find(:dialogue)
  annotation = Inspector.annotate(dialogue)

  assert.nil!(dialogue.object.h, "a wrap container with no explicit height never resolves h")
  assert.true!(annotation[:unresolved], "unresolved geometry is detected")
  assert.equal!(annotation[:kind], :unresolved, "the node classifies as unresolved")
end

def test_resolved_node_is_not_unresolved(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :box) do
      node({ w: 100, h: 50, primitive_marker: :solid }, id: :leaf)
    end
  end

  assert.false!(Inspector.annotate(ui.find(:leaf))[:unresolved], "a fully sized node is resolved")
end

# --- Overflow badge amount ----------------------------------------------------

def test_overflow_amount_reports_spill(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 300, w: 100, h: 100 }, id: :scroller, overflow: :scroll, justify: :start, align: :start, gap: 10) do
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :a)
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :b)
    end
  end

  scroller = ui.find(:scroller)
  # content span 170 (80 + 10 gap + 80) past the 100px box = 70px spill.
  assert.equal!(Inspector.annotate(scroller)[:overflow_amount], 70, "spill is content span minus box height")
end

def test_no_overflow_amount_when_content_fits(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 300, w: 100, h: 200 }, id: :box, justify: :start, align: :start) do
      node({ w: 80, h: 80, primitive_marker: :solid }, id: :a)
    end
  end

  assert.nil!(Inspector.annotate(ui.find(:box))[:overflow_amount], "content that fits has no spill")
end

# --- Node kind classification -------------------------------------------------

def test_kind_classification(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :outer) do
      node({ w: 100, h: 50, primitive_marker: :solid }, id: :leaf)
      node({ x: 0, y: 300, w: 100, h: 100 }, id: :scroller, overflow: :scroll) do
        node({ w: 80, h: 300, primitive_marker: :solid }, id: :tall)
      end
      node({ w: 40, h: 40, primitive_marker: :solid }, id: :floating, position: :absolute, top: 0, left: 0)
    end
  end

  assert.equal!(Inspector.annotate(ui.find(:outer))[:kind], :container, "a node with children is a container")
  assert.equal!(Inspector.annotate(ui.find(:leaf))[:kind], :leaf, "a childless renderable is a leaf")
  assert.equal!(Inspector.annotate(ui.find(:scroller))[:kind], :scroll, "a materialized scroll container is scroll")
  assert.equal!(Inspector.annotate(ui.find(:floating))[:kind], :out_of_flow, "an absolute child is out of flow")
end

# --- Deepest-node-at-point hit resolution -------------------------------------

def test_node_at_point_resolves_deepest(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :outer, direction: :column, justify: :start, align: :start) do
      node({ w: 200, h: 200, primitive_marker: :solid }, id: :inner)
    end
  end

  # inner spans x[0,200] y[200,400]; outer fills the 400x400 canvas.
  assert.equal!(Inspector.node_at_point(ui, 100, 300).id, :inner, "a point inside the inner box resolves to it")
  assert.equal!(Inspector.node_at_point(ui, 300, 100).id, :outer, "a point outside the inner box resolves to its container")
end

def test_node_at_point_nil_outside_the_tree(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 100, h: 100 }, id: :box) do
      node({ w: 50, h: 50, primitive_marker: :solid }, id: :leaf)
    end
  end

  # The point lies outside both :box and the root canvas origin corner it sits on.
  assert.nil!(Inspector.node_at_point(ui, 1000, 1000), "a point outside every box resolves to nothing")
end

def test_identity_falls_back_to_nearest_identified_ancestor(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :panel, direction: :column, justify: :start, align: :start) do
      node({ w: 100, h: 100, primitive_marker: :solid })
    end
  end

  anon = ui.find(:panel).children.first
  identity = Inspector.nearest_identity(anon)

  assert.equal!(identity[:id], :panel, "an unidentified node borrows its nearest identified ancestor")
  assert.equal!(identity[:path], [0], "with the child-index path down to it")
end

# --- Debug gate + emission ----------------------------------------------------

def test_inspector_emits_nothing_when_debug_off(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 400, h: 400 }, id: :box) do
      node({ w: 100, h: 50, primitive_marker: :solid }, id: :leaf)
    end
  end
  outputs = OutputsDouble.new

  Inspector.render(ui, outputs, { x: 100, y: 100 })

  assert.equal!(outputs.debug.length, 0, "the overlay builds nothing when debug? is false")
end

def test_inspector_emits_bounds_when_debug_on(args, assert)
  with_debug_game do
    ui = inspector_root do
      node({ x: 0, y: 0, w: 400, h: 400 }, id: :box) do
        node({ w: 100, h: 50, primitive_marker: :solid }, id: :leaf)
      end
    end
    outputs = OutputsDouble.new

    Inspector.render(ui, outputs, nil)

    borders = outputs.debug.select { |p| p[:primitive_marker] == :border }
    labels = outputs.debug.select { |p| p[:text] }
    assert.true!(borders.length >= 2, "a bounds border is emitted for the box and the leaf")
    assert.true!(labels.any? { |p| p[:text] == ":box" }, "the container id is labelled")
  end
end

def test_inspector_marks_unresolved_nodes_in_red(args, assert)
  with_debug_game do
    ui = inspector_root do
      node({ x: 0, y: 400, anchor_x: 0, anchor_y: 1 }, id: :dialogue, wrap: true) do
        node({ w: 100, h: 50, primitive_marker: :solid }, id: :box)
      end
    end
    outputs = OutputsDouble.new

    Inspector.render(ui, outputs, nil)

    red_label = outputs.debug.find { |p| p[:text] && p[:r] == 240 && p[:g] == 45 && p[:b] == 45 }
    assert.true!(!red_label.nil?, "the unresolved node gets a red label")
    assert.true!(red_label[:text].include?("h=nil"), "the label names the unresolved axis")
  end
end

def test_inspector_hover_readout_reports_provenance(args, assert)
  with_debug_game do
    ui = inspector_root do
      node({ x: 0, y: 0, w: 400, h: 400 }, id: :outer, direction: :column, justify: :start, align: :start) do
        node({ w: 200, h: 200, primitive_marker: :solid }, id: :inner)
      end
    end
    outputs = OutputsDouble.new

    Inspector.render(ui, outputs, { x: 100, y: 300 })

    text = outputs.debug.select { |p| p[:text] }.map { |p| p[:text] }.join(" | ")
    assert.true!(text.include?(":inner"), "the readout names the hovered node")
    assert.true!(text.include?("w: explicit"), "the readout reports per-axis provenance")
  end
end

# --- Box model: content + padding band ----------------------------------------

def test_box_model_padded_node_content_and_four_strips(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 200, h: 200 }, id: :box, padding: 20, justify: :start, align: :start) do
      node({ w: 50, h: 50, primitive_marker: :solid }, id: :child)
    end
  end

  model = Inspector.box_model(ui.find(:box))

  assert.equal!(model[:content], { x: 20, y: 20, w: 160, h: 160 }, "content is the rect inset by padding on every side")
  assert.equal!(model[:strips].length, 4, "a uniformly padded node has all four padding strips")

  top = model[:strips].find { |s| s[:edge] == :top }
  bottom = model[:strips].find { |s| s[:edge] == :bottom }
  left = model[:strips].find { |s| s[:edge] == :left }
  right = model[:strips].find { |s| s[:edge] == :right }

  assert.equal!([top[:x], top[:y], top[:w], top[:h]], [0, 180, 200, 20], "top strip spans the full width")
  assert.equal!([bottom[:x], bottom[:y], bottom[:w], bottom[:h]], [0, 0, 200, 20], "bottom strip spans the full width")
  assert.equal!([left[:x], left[:y], left[:w], left[:h]], [0, 20, 20, 160], "left strip fills only the middle band")
  assert.equal!([right[:x], right[:y], right[:w], right[:h]], [180, 20, 20, 160], "right strip fills only the middle band")
end

def test_box_model_zero_padding_yields_no_strips_and_full_content(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 100, h: 100 }, id: :box, justify: :start, align: :start) do
      node({ w: 40, h: 40, primitive_marker: :solid }, id: :child)
    end
  end

  model = Inspector.box_model(ui.find(:box))

  assert.equal!(model[:strips].length, 0, "a zero-padding node emits no padding strips")
  assert.equal!(model[:content], { x: 0, y: 0, w: 100, h: 100 }, "content fills the whole rect")
end

def test_box_model_respects_per_side_padding(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 200, h: 200 }, id: :box, padding: { left: 10, right: 20, top: 30, bottom: 40 }, justify: :start, align: :start) do
      node({ w: 40, h: 40, primitive_marker: :solid }, id: :child)
    end
  end

  model = Inspector.box_model(ui.find(:box))

  assert.equal!(model[:padding], { left: 10, right: 20, top: 30, bottom: 40 }, "per-side padding is read as layout normalized it")
  assert.equal!(model[:content], { x: 10, y: 40, w: 170, h: 130 }, "content respects each side's inset")
  assert.equal!(model[:strips].length, 4, "all four sides are present")
end

# --- Box model: gap strips ----------------------------------------------------

def test_gap_strips_row_between_children(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 300, h: 100 }, id: :bar, direction: :row, justify: :start, align: :start, gap: 20) do
      node({ w: 80, h: 60, primitive_marker: :solid }, id: :a)
      node({ w: 80, h: 60, primitive_marker: :solid }, id: :b)
    end
  end

  gaps = Inspector.box_model(ui.find(:bar))[:gaps]

  assert.equal!(gaps.length, 1, "one gap strip between the two children")
  assert.equal!([gaps[0][:x], gaps[0][:y], gaps[0][:w], gaps[0][:h]], [80, 0, 20, 100],
                "a vertical strip filling the space between the boxes, spanning the content height")
end

def test_gap_strips_column_between_children(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 200, w: 100, h: 200 }, id: :col, direction: :column, justify: :start, align: :start, gap: 15) do
      node({ w: 60, h: 50, primitive_marker: :solid }, id: :a)
      node({ w: 60, h: 50, primitive_marker: :solid }, id: :b)
    end
  end

  gaps = Inspector.box_model(ui.find(:col))[:gaps]

  assert.equal!(gaps.length, 1, "one gap strip between the two stacked children")
  assert.equal!([gaps[0][:x], gaps[0][:y], gaps[0][:w], gaps[0][:h]], [0, 335, 100, 15],
                "a horizontal strip filling the vertical space between the boxes, spanning the content width")
end

def test_no_gap_strips_when_gap_zero(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 300, h: 100 }, id: :bar, direction: :row, justify: :start, align: :start, gap: 0) do
      node({ w: 80, h: 60, primitive_marker: :solid }, id: :a)
      node({ w: 80, h: 60, primitive_marker: :solid }, id: :b)
    end
  end

  assert.equal!(Inspector.box_model(ui.find(:bar))[:gaps].length, 0, "gap: 0 produces no gap strips")
end

def test_absolute_children_do_not_form_gap_pairs(args, assert)
  ui = inspector_root do
    node({ x: 0, y: 0, w: 300, h: 100 }, id: :bar, direction: :row, justify: :start, align: :start, gap: 20) do
      node({ w: 80, h: 60, primitive_marker: :solid }, id: :a)
      node({ w: 40, h: 40, primitive_marker: :solid }, id: :floating, position: :absolute, top: 0, left: 0)
      node({ w: 80, h: 60, primitive_marker: :solid }, id: :c)
    end
  end

  gaps = Inspector.box_model(ui.find(:bar))[:gaps]

  # a and c are the only in-flow children: c flows right after a (+gap), so there
  # is exactly one gap pair and the absolute node is not part of it.
  assert.equal!(gaps.length, 1, "the absolute child is excluded from gap pairing")
  assert.equal!([gaps[0][:x], gaps[0][:w]], [80, 20], "the single gap sits between the two in-flow children")
end

# --- Box model emission + readout ---------------------------------------------

def test_hover_emits_content_padding_and_gap_fills(args, assert)
  with_debug_game do
    ui = inspector_root do
      node({ x: 0, y: 0, w: 300, h: 100 }, id: :bar, direction: :row, justify: :start, align: :start, gap: 20, padding: 10) do
        node({ w: 80, h: 60, primitive_marker: :solid }, id: :a)
        node({ w: 80, h: 60, primitive_marker: :solid }, id: :b)
      end
    end
    outputs = OutputsDouble.new

    # A point inside the bar but over the gap, so the deepest node is the bar.
    Inspector.render(ui, outputs, { x: 95, y: 50 })

    solids = outputs.debug.select { |p| p[:primitive_marker] == :solid }
    assert.true!(solids.any? { |p| p[:r] == 100 && p[:g] == 160 && p[:b] == 240 }, "a translucent blue content fill is emitted")
    assert.true!(solids.any? { |p| p[:r] == 130 && p[:g] == 200 && p[:b] == 120 }, "a translucent green padding strip is emitted")
    assert.true!(solids.any? { |p| p[:r] == 175 && p[:g] == 120 && p[:b] == 220 }, "a translucent purple gap strip is emitted")

    text = outputs.debug.select { |p| p[:text] }.map { |p| p[:text] }.join(" | ")
    assert.true!(text.include?("padding: 10"), "the readout reports padding")
    assert.true!(text.include?("gap: 20"), "the readout reports gap")
  end
end

def test_hover_readout_reports_per_side_padding(args, assert)
  with_debug_game do
    ui = inspector_root do
      node({ x: 0, y: 0, w: 300, h: 200 }, id: :bar, direction: :row, justify: :start, align: :start, padding: { left: 5, right: 10, top: 15, bottom: 20 }) do
        node({ w: 80, h: 60, primitive_marker: :solid }, id: :a)
      end
    end
    outputs = OutputsDouble.new

    Inspector.render(ui, outputs, { x: 150, y: 100 })

    text = outputs.debug.select { |p| p[:text] }.map { |p| p[:text] }.join(" | ")
    assert.true!(text.include?("padding: t15 r10 b20 l5"), "non-uniform padding is shown per side")
  end
end
