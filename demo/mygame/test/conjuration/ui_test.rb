require "lib/conjuration"

# test_[direction]_[justify]_[align]_[padding]_[gap]

ROOT = { x: 0, y: 0, w: 400, h: 400 }

def test_column_start_start(args, assert)
  actual = Conjuration::UI.build(ROOT, direction: :column, justify: :start, align: :start) do
    node({ w: 100, h: 100, test_id: "node1", primitive_marker: :solid })
    node({ w: 100, h: 100, test_id: "node2", primitive_marker: :solid })
  end

  expected = [
    {
      x: 0,
      y: 400,
      w: 100,
      h: 100,
      anchor_x: 0,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node1"
    },
    {
      x: 0,
      y: 300,
      w: 100,
      h: 100,
      anchor_x: 0,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node2"
    }
  ]

  assert.equal!(actual.primitives, expected)
end

def test_column_start_start_10(args, assert)
  actual = Conjuration::UI.build(ROOT, direction: :column, justify: :start, align: :start, padding: 10) do
    node({ w: 100, h: 100, test_id: "node1", primitive_marker: :solid })
    node({ w: 100, h: 100, test_id: "node2", primitive_marker: :solid })
  end

  expected = [
    {
      x: 10,
      y: 390,
      w: 100,
      h: 100,
      anchor_x: 0,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node1"
    },
    {
      x: 10,
      y: 290,
      w: 100,
      h: 100,
      anchor_x: 0,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node2"
    }
  ]

  assert.equal!(actual.primitives, expected)
end

def test_column_start_start_10_10(args, assert)
  actual = Conjuration::UI.build(ROOT, direction: :column, justify: :start, align: :start, padding: 10, gap: 10) do
    node({ w: 100, h: 100, test_id: "node1", primitive_marker: :solid })
    node({ w: 100, h: 100, test_id: "node2", primitive_marker: :solid })
  end

  expected = [
    {
      x: 10,
      y: 390,
      w: 100,
      h: 100,
      anchor_x: 0,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node1"
    },
    {
      x: 10,
      y: 280,
      w: 100,
      h: 100,
      anchor_x: 0,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node2"
    }
  ]

  assert.equal!(actual.primitives, expected)
end

def test_column_start_center(args, assert)
  actual = Conjuration::UI.build(ROOT, direction: :column, justify: :start, align: :center) do
    node({ w: 100, h: 100, test_id: "node1", primitive_marker: :solid })
    node({ w: 100, h: 100, test_id: "node2", primitive_marker: :solid })
  end

  expected = [
    {
      x: 200,
      y: 400,
      w: 100,
      h: 100,
      anchor_x: 0.5,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node1"
    },
    {
      x: 200,
      y: 300,
      w: 100,
      h: 100,
      anchor_x: 0.5,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node2"
    }
  ]

  assert.equal!(actual.primitives, expected)
end

def test_column_start_center_10(args, assert)
  actual = Conjuration::UI.build(ROOT, direction: :column, justify: :start, align: :center, padding: 10) do
    node({ w: 100, h: 100, test_id: "node1", primitive_marker: :solid })
    node({ w: 100, h: 100, test_id: "node2", primitive_marker: :solid })
  end

  expected = [
    {
      x: 200,
      y: 390,
      w: 100,
      h: 100,
      anchor_x: 0.5,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node1"
    },
    {
      x: 200,
      y: 290,
      w: 100,
      h: 100,
      anchor_x: 0.5,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node2"
    }
  ]

  assert.equal!(actual.primitives, expected)
end

def test_column_start_center_10_10(args, assert)
  actual = Conjuration::UI.build(ROOT, direction: :column, justify: :start, align: :center, padding: 10, gap: 10) do
    node({ w: 100, h: 100, test_id: "node1", primitive_marker: :solid })
    node({ w: 100, h: 100, test_id: "node2", primitive_marker: :solid })
  end

  expected = [
    {
      x: 200,
      y: 390,
      w: 100,
      h: 100,
      anchor_x: 0.5,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node1"
    },
    {
      x: 200,
      y: 280,
      w: 100,
      h: 100,
      anchor_x: 0.5,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node2"
    }
  ]

  assert.equal!(actual.primitives, expected)
end

def test_column_start_end(args, assert)
  actual = Conjuration::UI.build(ROOT, direction: :column, justify: :start, align: :end) do
    node({ w: 100, h: 100, test_id: "node1", primitive_marker: :solid })
    node({ w: 100, h: 100, test_id: "node2", primitive_marker: :solid })
  end

  expected = [
    {
      x: 400,
      y: 400,
      w: 100,
      h: 100,
      anchor_x: 1,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node1"
    },
    {
      x: 400,
      y: 300,
      w: 100,
      h: 100,
      anchor_x: 1,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node2"
    }
  ]

  assert.equal!(actual.primitives, expected)
end

def test_column_start_end_10(args, assert)
  actual = Conjuration::UI.build(ROOT, direction: :column, justify: :start, align: :end, padding: 10) do
    node({ w: 100, h: 100, test_id: "node1", primitive_marker: :solid })
    node({ w: 100, h: 100, test_id: "node2", primitive_marker: :solid })
  end

  expected = [
    {
      x: 390,
      y: 390,
      w: 100,
      h: 100,
      anchor_x: 1,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node1"
    },
    {
      x: 390,
      y: 290,
      w: 100,
      h: 100,
      anchor_x: 1,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node2"
    }
  ]

  assert.equal!(actual.primitives, expected)
end

def test_column_start_end_10_10(args, assert)
  actual = Conjuration::UI.build(ROOT, direction: :column, justify: :start, align: :end, padding: 10, gap: 10) do
    node({ w: 100, h: 100, test_id: "node1", primitive_marker: :solid })
    node({ w: 100, h: 100, test_id: "node2", primitive_marker: :solid })
  end

  expected = [
    {
      x: 390,
      y: 390,
      w: 100,
      h: 100,
      anchor_x: 1,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node1"
    },
    {
      x: 390,
      y: 280,
      w: 100,
      h: 100,
      anchor_x: 1,
      anchor_y: 1,
      primitive_marker: :solid,
      test_id: "node2"
    }
  ]

  assert.equal!(actual.primitives, expected)
end
