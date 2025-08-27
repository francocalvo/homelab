# Lib Directory

This directory contains utility functions and helper modules for the homelab Nix configuration. The library is structured as an extensible attribute set that provides various utilities for working with NixOS configurations, attribute sets, modules, and more.

## Structure

- `default.nix` - Main entry point that creates an extensible library from all modules
- `attrs.nix` - Attribute set manipulation utilities
- `generators.nix` - File and resource generation utilities
- `modules.nix` - Module discovery and mapping utilities
- `nixos.nix` - NixOS system building utilities
- `options.nix` - Option definition helpers
- `systems.nix` - Multi-system and architecture utilities
- `utils.nix` - General utility functions

## Core Utilities

### Attribute Set Utilities (`attrs.nix`)

Helper functions for working with attribute sets:

- **`attrsToList`** - Convert an attribute set to a list of name-value pairs
- **`mapFilterAttrs`** - Map and filter attributes in one operation
- **`genAttrs'`** - Generate attribute set by mapping function over list of values
- **`anyAttrs`** - Check if any attribute satisfies a predicate
- **`countAttrs`** - Count attributes that satisfy a predicate

### Module Discovery (`modules.nix`)

Functions for discovering and mapping Nix modules in directories:

- **`mapModules`** - Map a function over all `.nix` files in a directory, creating an attribute set
- **`mapModules'`** - Same as `mapModules` but returns a list of values
- **`mapModulesRec`** - Recursively map modules in nested directories
- **`mapModulesRec'`** - Recursive version that returns flattened list of paths

These functions automatically:
- Skip files/directories starting with `_`
- Handle directories with `default.nix` files
- Remove `.nix` extensions from attribute names

### NixOS System Building (`nixos.nix`)

Utilities for creating NixOS systems:

- **`mkHost`** - Create a NixOS system configuration from a path and attributes
  - Defaults to `x86_64-linux` system
  - Sets hostname from filename
  - Includes common modules and imports
- **`mapHosts`** - Apply `mkHost` to all modules in a directory

### Option Helpers (`options.nix`)

Simplified option definition functions:

- **`mkOpt`** - Create option with type and default value
- **`mkOpt'`** - Create option with type, default, and description
- **`mkBoolOpt`** - Create boolean option with default value

### File Generators (`generators.nix`)

Utilities for generating files and resources:

- **`toCSSFile`** - Compile SCSS files to CSS using Sass
  - Removes sourcemaps
  - Uses compressed style
  - UTF-8 encoding
- **`toFilteredImage`** - Apply ImageMagick filters to images
  - Takes image file and filter options
  - Outputs processed PNG

### System Utilities (`systems.nix`)

Multi-system and architecture support functions:

- **`supportedSystems`** - List of supported system architectures (`["x86_64-linux" "aarch64-linux"]`)

### General Utils (`utils.nix`)

Common utility values:

- **`enable`** - Shorthand for `{ enable = true; }`
- **`disable`** - Shorthand for `{ enable = false; }`

## Usage

The library is designed to be imported and used throughout your NixOS configuration:

```nix
{ lib, ... }:
let
  inherit (lib.my) mkHost mapModules enable;
in {
  # Use library functions
}
```

The main `default.nix` creates an extensible library that automatically imports all modules in the directory, making all functions available under appropriate namespaces.

## Extension

The library uses `lib.makeExtensible` which allows you to extend it with additional functionality as needed. New `.nix` files added to this directory will automatically be included in the library.
