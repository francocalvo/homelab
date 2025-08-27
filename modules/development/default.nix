# Development module - provides development environment configurations
{ config, lib, pkgs, ... }:

with lib;
let cfg = config.modules.development;
in {
  options.modules.development = {
    enable = mkBoolOpt false;
    languages = {
      rust.enable = mkBoolOpt false;
      nodejs.enable = mkBoolOpt false;
      python.enable = mkBoolOpt false;
      go.enable = mkBoolOpt false;
      nix.enable = mkBoolOpt true;
    };
    tools = {
      git.enable = mkBoolOpt true;
      direnv.enable = mkBoolOpt true;
      tmux.enable = mkBoolOpt false;
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base development tools
    {
      environment.systemPackages = with pkgs; [
        curl
        wget
        jq
        tree
        file
        unzip
        zip
        htop
        btop
        ripgrep
        fd
        fzf
        bat
        eza
      ];
    }

    # Rust development
    (mkIf cfg.languages.rust.enable {
      environment.systemPackages = with pkgs; [
        rustc
        cargo
        rustfmt
        rust-analyzer
        clippy
      ];
    })

    # Node.js development
    (mkIf cfg.languages.nodejs.enable {
      environment.systemPackages = with pkgs; [
        nodejs
        yarn
        nodePackages.npm
        nodePackages.pnpm
        nodePackages.typescript
        nodePackages.typescript-language-server
      ];
    })

    # Python development
    (mkIf cfg.languages.python.enable {
      environment.systemPackages = with pkgs; [
        python3
        python3Packages.pip
        python3Packages.virtualenv
        python3Packages.pytest
        python3Packages.black
        python3Packages.flake8
        python3Packages.pylsp-mypy
        python311Packages.python-lsp-server
      ];
    })

    # Go development
    (mkIf cfg.languages.go.enable {
      environment.systemPackages = with pkgs; [
        go
        gopls
        delve
        golangci-lint
      ];
    })

    # Nix development
    (mkIf cfg.languages.nix.enable {
      environment.systemPackages = with pkgs; [
        nixd
        nixfmt-rfc-style
        nix-tree
        nix-diff
        nix-output-monitor
        nvd
      ];
    })

    # Git configuration
    (mkIf cfg.tools.git.enable {
      programs.git = {
        enable = true;
        config = {
          init.defaultBranch = "main";
          pull.rebase = true;
          rebase.autoStash = true;
        };
      };

      environment.systemPackages = with pkgs; [
        git
        git-lfs
        gh # GitHub CLI
        lazygit
      ];
    })

    # Direnv for automatic environment loading
    (mkIf cfg.tools.direnv.enable {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    })

    # Tmux terminal multiplexer
    (mkIf cfg.tools.tmux.enable {
      programs.tmux = {
        enable = true;
        extraConfig = ''
          # Set prefix to Ctrl-a
          set -g prefix C-a
          unbind C-b
          bind C-a send-prefix

          # Enable mouse support
          set -g mouse on

          # Start windows and panes at 1
          set -g base-index 1
          setw -g pane-base-index 1

          # Reload config with r
          bind r source-file ~/.tmux.conf \; display "Config reloaded!"

          # Better splitting
          bind | split-window -h
          bind - split-window -v
        '';
      };
    })
  ]);
}
