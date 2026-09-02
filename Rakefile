ROOT = __dir__

desc "Check every app in apps/ (runs before registry)"
task :validate do
  require_relative "tools/validate"
  errors = Validate.run(ROOT)
  if errors.empty?
    puts "validate: #{Dir.children(File.join(ROOT, 'apps')).size} apps, no problems"
  else
    errors.each { |e| warn "  #{e}" }
    abort "validate: #{errors.size} problem(s)"
  end
end

desc "Regenerate registry.json (and the device thumbnails) from apps/"
task registry: :validate do
  require_relative "tools/registry"
  data = Registry.build(ROOT)
  json = File.join(ROOT, "registry.json")
  tsv  = File.join(ROOT, "registry.tsv")
  File.write(json, Registry.render(data))
  File.write(tsv, Registry.render_tsv(data))
  puts "registry: wrote #{File.size(json)} + #{File.size(tsv)} bytes"
end

desc "Check that the checks still catch what they are meant to"
task :selftest do
  require_relative "tools/selftest"
  failures = Selftest.run(ROOT)
  if failures.empty?
    puts "selftest: #{Selftest::CASES.size} specimens, all caught"
  else
    failures.each { |f| warn "  #{f}" }
    abort "selftest: #{failures.size} check(s) no longer bite"
  end
end

desc "Fail when registry.json in the tree is not what apps/ generates"
task check_registry: :registry do
  # Both directions matter: a tracked file that regeneration changed, and a
  # generated file that was never committed at all (git diff says nothing
  # about an untracked file, so ask status as well).
  dirty = `git -C #{ROOT.inspect} status --porcelain -- registry.json apps`.split("\n")
  next if dirty.empty?
  dirty.each { |line| warn "  #{line}" }
  abort "registry.json, registry.tsv or a thumbnail is not what apps/ generates -- " \
        "run `rake registry` and commit the result"
end

task default: %i[selftest check_registry]
