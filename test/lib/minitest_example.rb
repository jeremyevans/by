ENV['MT_NO_PLUGINS'] = '1' # Work around stupid autoloading of plugins
require 'minitest/global_expectations/autorun'

describe "example" do
  it "should work" do
    ENV['MINITEST_FAIL'].must_be_nil
  end

  it "should always work" do
    nil.must_be_nil
    1.must_equal 1
  end
end
