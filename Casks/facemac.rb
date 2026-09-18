cask "facemac" do
  version "0.1.1"
  # Replace with `shasum -a 256 FaceMac-#{version}.dmg` output once the build is
  # Developer ID signed and notarized. `:no_check` is fine for a personal tap.
  sha256 :no_check

  url "https://github.com/c1osed1/FaceMac/releases/download/v#{version}/FaceMac-#{version}.dmg",
      verified: "github.com/c1osed1/FaceMac/"
  name "FaceMac"
  desc "On-device face unlock for macOS"
  homepage "https://github.com/c1osed1/FaceMac"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "FaceMac.app"

  zap trash: [
    "~/Library/Preferences/com.facemac.app.plist",
    "~/Library/Application Support/FaceMac",
  ]

  caveat <<~EOS
    FaceMac releases are not notarized yet, so Gatekeeper will warn on first
    launch. Install with `--no-quarantine`, or right-click the app and choose
    Open once after installing.
  EOS
end
