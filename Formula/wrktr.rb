# Homebrew formula for wrktr.
#
# This formula is intended for a personal tap (homebrew-wrktr).
# To use it:
#
#   brew tap your-username/wrktr
#   brew install wrktr
#
# To create the tap:
#   1. Create a GitHub repository named homebrew-wrktr
#   2. Copy this file there as Formula/wrktr.rb
#   3. Update the url and sha256 fields below to point to a tagged release
#
# To generate the sha256 for a release tarball:
#   curl -fsSL <url> | shasum -a 256

class Wrktr < Formula
  desc "Branch-as-directory git worktree session manager"
  homepage "https://github.com/your-username/wrktr"
  url "https://github.com/your-username/wrktr/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  version "1.0.0"

  # wrktr targets bash 3.2 (the macOS system default) and does not require
  # a newer bash. This dependency is optional: install it if you want bash 5+,
  # but it is not required for the tool to function.
  # depends_on "bash" => :optional

  def install
    # Install the main script to libexec so it is not on PATH
    # (wrktr is sourced, not run as a standalone command)
    libexec.install "worktree-functions.sh"

    # Install the man page
    man1.install "docs/wrktr.1"

    # Write a shell integration shim that other formulas or users can source
    (prefix/"etc/wrktr/wrktr.sh").write <<~EOS
      # wrktr shell integration — source this file to load wrktr functions
      # shellcheck shell=bash
      source "#{libexec}/worktree-functions.sh"
    EOS
  end

  def caveats
    <<~EOS
      wrktr is a shell function library, not a standalone command.
      To use it, add the following line to your shell profile
      (~/.zshrc or ~/.bash_profile):

        source "#{prefix}/etc/wrktr/wrktr.sh"

      Or run this one-time command to add it automatically:

        echo 'source "#{prefix}/etc/wrktr/wrktr.sh"' >> ~/.zshrc

      After reloading your shell:

        wrktr_clone https://github.com/user/myapp.git
        wrktr_generate myapp
        wrktr_use myapp

      Full documentation: man wrktr
    EOS
  end

  test do
    # Source the functions and confirm the version variable is set
    output = shell_output("bash -c 'source #{libexec}/worktree-functions.sh && echo $WRKTR_VERSION'")
    assert_match "1.0.0", output

    # Confirm the sanitize helper encodes slashes correctly
    encoded = shell_output("bash -c 'source #{libexec}/worktree-functions.sh && _wrktr_sanitize_branch_name feature/login'")
    assert_match "feature%2Flogin", encoded
  end
end
