RSpec.describe "example" do
  it "should work" do
    expect(ENV['RSPEC_FAIL']).to be_nil
  end

  it "should always work" do
    expect(nil).to be_nil
    expect(1).to eq 1
  end
end
