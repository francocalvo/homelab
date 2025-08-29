# Editor module - provides various editor configurations
{ config, lib, pkgs, ... }:

with lib;
let cfg = config.modules.editor;
in {
  options.modules.editor = {
    neovim.enable = mkBoolOpt false;
    vscode.enable = mkBoolOpt false;
    emacs.enable = mkBoolOpt false;
  };

  config = mkMerge [
    (mkIf cfg.neovim.enable {
      environment.systemPackages = with pkgs; [
        neovim
        # Add common neovim dependencies
        nodejs  # for language servers
        python3 # for python plugins
        ripgrep # for search
        fd      # for file finding
        git     # for git integration
      ];

      environment.variables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };

      # Create a basic nvim configuration
      environment.etc."nvim/init.vim".text = ''
        " Basic Neovim configuration
        set number
        set relativenumber
        set expandtab
        set tabstop=2
        set shiftwidth=2
        set autoindent
        set smartindent
        syntax enable
        
        " Enable mouse support
        set mouse=a
        
        " Search improvements
        set ignorecase
        set smartcase
        set incsearch
        set hlsearch
      '';
    })

    (mkIf cfg.vscode.enable {
      environment.systemPackages = with pkgs; [
        vscode
        # Common VS Code extensions and dependencies
        nodejs
        python3
        git
      ];
    })

    (mkIf cfg.emacs.enable {
      environment.systemPackages = with pkgs; [
        emacs
        # Emacs dependencies
        git
        ripgrep
        fd
      ];

      environment.variables = {
        EDITOR = mkIf (!cfg.neovim.enable) "emacs";
      };
    })
  ];
}
