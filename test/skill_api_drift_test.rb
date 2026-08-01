# Drift guard for skills/conjuration: every `Receiver#member` / `Receiver.member`
# identifier the shipped agent skill quotes in prose must still name something
# lib/ defines. Source grep, not reflection — the point is to catch a rename in
# lib that leaves the skill telling agents about an API that no longer exists.
#
# Deliberately narrow: only receivers in SKILL_GUARD_RECEIVERS are checked, so
# dragon_input's and DragonRuby's own surface stays out of scope. The harness has
# no Dir and no Regexp, so both file discovery and scanning are done by hand —
# the lib file list comes from walking require_relative, and the skill file list
# from the references SKILL.md itself links.

SKILL_GUARD_ENTRY = "skills/conjuration/SKILL.md".freeze
SKILL_GUARD_LIB_ENTRY = "lib/conjuration.rb".freeze

SKILL_GUARD_RECEIVERS = [
  "Conjuration::UI", "Conjuration::Scene", "Conjuration::Game", "Conjuration::Node",
  "Conjuration::Camera", "Conjuration::Animation", "Conjuration::TileLayer",
  "UI", "Scene", "Game", "Node", "Camera", "Animation", "Hash"
].freeze

# Universally available on every object; naming one is never a claim about lib.
SKILL_GUARD_IGNORED_MEMBERS = ["new", "class", "dup", "send", "to_s", "inspect"].freeze

def skill_guard_identifier_char?(char)
  return false if char.nil?

  (char >= "a" && char <= "z") || (char >= "A" && char <= "Z") ||
    (char >= "0" && char <= "9") || char == "_"
end

# The identifier starting at `from`, plus a trailing ? or ! — or nil.
def skill_guard_member_at(text, from)
  cursor = from
  cursor += 1 while skill_guard_identifier_char?(text[cursor])
  return nil if cursor == from

  suffix = text[cursor]
  cursor += 1 if suffix == "?" || suffix == "!"
  text[from...cursor]
end

# Every `require_relative`-reachable file from `entry`, in discovery order.
def skill_guard_lib_files(entry, seen = [])
  return seen if seen.include?(entry)

  seen << entry
  parts = entry.split("/")
  dir = parts[0...-1].join("/")

  File.read(entry).split("\n").each do |line|
    stripped = line.strip
    next unless stripped.start_with?("require_relative ")

    rest = stripped["require_relative ".length..-1].strip
    quote = rest[0]
    close = rest.index(quote, 1)
    next if close.nil?

    skill_guard_lib_files("#{dir}/#{rest[1...close]}.rb", seen)
  end

  seen
end

# Symbols named on a line: `:foo`, `:foo?`. Used for attr_*/delegate lists.
def skill_guard_symbols(line)
  found = []
  index = line.index(":")
  while index
    member = skill_guard_member_at(line, index + 1)
    found << member if member
    index = line.index(":", index + 1)
  end
  found
end

# Names lib/ defines or probes for: def, attr_*, delegate, alias, and the
# duck-typed hooks it reaches through respond_to?(:hook).
def skill_guard_lib_names(files)
  names = []

  files.each do |path|
    File.read(path).split("\n").each do |line|
      stripped = line.strip

      if stripped.start_with?("def ")
        start = 4
        start += 5 if stripped[start, 5] == "self."
        member = skill_guard_member_at(stripped, start)
        names << member if member
      end

      if stripped.start_with?("attr_accessor ") || stripped.start_with?("attr_reader ") ||
         stripped.start_with?("attr_writer ") || stripped.start_with?("delegate ")
        names.concat(skill_guard_symbols(stripped))
      end

      if stripped.start_with?("alias ")
        stripped.split(" ")[1..-1].to_a.each { |word| names << word }
      end

      probe = stripped.index("respond_to?(:")
      while probe
        member = skill_guard_member_at(stripped, probe + 13)
        names << member if member
        probe = stripped.index("respond_to?(:", probe + 1)
      end
    end
  end

  names
end

# The skill's own files: SKILL.md plus every references/*.md it links.
def skill_guard_skill_files
  files = [SKILL_GUARD_ENTRY]
  content = File.read(SKILL_GUARD_ENTRY)
  marker = "references/"

  index = content.index(marker)
  while index
    name = skill_guard_member_at(content, index + marker.length)
    files << "skills/conjuration/#{marker}#{name}.md" if name && content[index + marker.length + name.length, 3] == ".md"
    index = content.index(marker, index + 1)
  end

  files.uniq
end

# Scannable text: whole lines inside fenced blocks, backticked spans outside.
# Splitting prose on backticks only works once the fences are accounted for —
# a ``` line would otherwise flip the span parity for the rest of the file.
def skill_guard_code_spans(content)
  spans = []
  fenced = false

  content.split("\n").each do |line|
    if line.strip.start_with?("```")
      fenced = !fenced
      next
    end

    if fenced
      spans << line
      next
    end

    parts = line.split("`")
    index = 1
    while index < parts.length
      spans << parts[index]
      index += 2
    end
  end

  spans
end

# [receiver, member] pairs naming a Conjuration API inside one code span.
def skill_guard_identifiers(span)
  found = []

  SKILL_GUARD_RECEIVERS.each do |receiver|
    ["#", "."].each do |separator|
      needle = "#{receiver}#{separator}"
      at = span.index(needle)
      while at
        before = at.zero? ? nil : span[at - 1]
        # A longer receiver owns the match: `Conjuration::UI.x` is not `UI.x`.
        unless skill_guard_identifier_char?(before) || before == ":" || before == "." || before == "#"
          member = skill_guard_member_at(span, at + needle.length)
          found << [receiver, member] if member && !SKILL_GUARD_IGNORED_MEMBERS.include?(member)
        end
        at = span.index(needle, at + 1)
      end
    end
  end

  found
end

def test_skill_identifiers_still_resolve_in_lib(args, assert)
  known = skill_guard_lib_names(skill_guard_lib_files(SKILL_GUARD_LIB_ENTRY))
  checked = 0
  missing = []

  skill_guard_skill_files.each do |path|
    skill_guard_code_spans(File.read(path)).each do |span|
      skill_guard_identifiers(span).each do |(receiver, member)|
        checked += 1
        missing << "#{path}: #{receiver} -> #{member}" unless known.include?(member)
      end
    end
  end

  assert.equal!(missing, [], "skills/ names APIs lib/ no longer defines")
  assert.true!(checked >= 25, "the guard extracted only #{checked} identifiers — the scanner is probably broken")
end
