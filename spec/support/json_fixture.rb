module JsonFixture
  def json_fixture(name)
    path = Rails.root.join("spec/fixtures", name)
    JSON.parse(File.read(path))
  end
end

RSpec.configure { |c| c.include JsonFixture }
