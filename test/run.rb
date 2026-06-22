# Test runner entry point.
#
# By the time this runs, script/test.sh has preloaded (via `mruby -r`) the
# shims, the lib, the doubles, and every test/*_test.rb. Each test file defines
# top-level `def test_*(args, assert)` methods (DragonRuby's signature). Here we
# discover and run them, printing a dot/F/E per test and exiting non-zero on any
# failure so CI fails loudly.

assert = Assert.new
args = $game

names = private_methods
  .map { |m| m.to_s }
  .select { |m| m.start_with?("test_") }
  .sort

passed = 0
failures = []

names.each do |name|
  begin
    send(name, args, assert)
    passed += 1
    print "."
  rescue AssertionError => e
    failures << [name, e.message]
    print "F"
  rescue => e
    failures << [name, "#{e.class}: #{e.message}"]
    print "E"
  end
end

print "\n\n"
failures.each do |(name, message)|
  puts "FAIL #{name}"
  puts "  #{message}"
end
puts "#{passed} passed, #{failures.length} failed"

# Signal the result to the shell. CRuby and DragonRuby have Kernel#exit; the
# standalone mruby-patched build does not, but it exits non-zero on an uncaught
# raise and zero on normal completion — so raise to fail, return to pass.
if respond_to?(:exit, true)
  exit(failures.empty? ? 0 : 1)
elsif failures.any?
  raise "#{failures.length} test(s) failed"
end
