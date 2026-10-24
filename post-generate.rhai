let cli_name = variable::get("cli_bin_name");

if cli_name != "my-cli" {
    file::rename("crates/my-cli", `crates/${cli_name}`);
}

// Clean up the hook script from the generated repository
file::delete("post-generate.rhai");

print("✨ Workspace generated! Run `nix develop --command just init` to bootstrap hooks and baseline tags.");
