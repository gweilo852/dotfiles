-- WezTerm: managed by dotfiles (https://github.com/gweilo852/dotfiles).
-- Low-glare Catppuccin Macchiato with muted text, an opaque background and
-- a steady cursor. The same file is used on macOS, Windows and Linux.
--
-- Per-machine changes (font size, weight, brightness) belong in
-- wezterm_local.lua next to this file. See docs/customization.md.

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local is_macos = wezterm.target_triple:find('darwin') ~= nil
local is_windows = wezterm.target_triple:find('windows') ~= nil

-- ============================================================
-- FONT
-- ============================================================

config.font = wezterm.font('CaskaydiaMono Nerd Font Mono', { weight = 'DemiBold' })
config.font_size = 13.5

-- Programming ligatures
config.harfbuzz_features = { 'calt=1', 'clig=1', 'liga=1' }

-- Comfortable line spacing
config.line_height = 1.1

-- ============================================================
-- COLOURS - soft, low-glare Catppuccin Macchiato
-- ============================================================

config.color_scheme = 'Catppuccin Macchiato'

-- Text is one step dimmer than the scheme's #cad3f5, and "white" matches it,
-- so long sessions are easier on the eyes. The background stays the
-- scheme's base colour.
config.colors = {
  foreground = '#b8c0d9',
  background = '#24273a',

  cursor_bg = '#a5adcb',
  cursor_fg = '#24273a',
  cursor_border = '#a5adcb',

  selection_bg = '#494d64',
  selection_fg = '#cad3f5',

  ansi = {
    '#494d64', -- black
    '#ed8796', -- red
    '#a6da95', -- green
    '#eed49f', -- yellow
    '#8aadf4', -- blue
    '#c6a0f6', -- magenta
    '#8bd5ca', -- cyan
    '#b8c0d9', -- white
  },
  brights = {
    '#5b6078', -- bright black
    '#ed8796', -- bright red
    '#a6da95', -- bright green
    '#eed49f', -- bright yellow
    '#8aadf4', -- bright blue
    '#c6a0f6', -- bright magenta
    '#8bd5ca', -- bright cyan
    '#cad3f5', -- bright white
  },
}

-- ============================================================
-- WINDOW
-- ============================================================

-- Opaque, so bright windows behind the terminal do not bleed through.
config.window_background_opacity = 1.0

config.window_padding = { left = 14, right = 14, top = 12, bottom = 12 }
config.enable_scroll_bar = false

-- ============================================================
-- CURSOR
-- ============================================================

-- A steady cursor avoids distracting blinking.
config.default_cursor_style = 'SteadyBar'
config.cursor_thickness = 2

-- ============================================================
-- TABS
-- ============================================================

-- Minimal tab bar, hidden when only one tab is open.
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true

-- ============================================================
-- GENERAL
-- ============================================================

-- Inline images (for example from `wezterm imgcat`).
config.enable_kitty_graphics = true
config.automatically_reload_config = true

-- ============================================================
-- PLATFORM-SPECIFIC
-- ============================================================

if is_macos then
  config.macos_window_background_blur = 0
  -- Left Option acts as Alt (needed for fzf Alt+C); right Option still
  -- types special characters.
  config.send_composed_key_when_left_alt_is_pressed = false
  config.send_composed_key_when_right_alt_is_pressed = true
end

if is_windows then
  -- Open WSL in the Linux home directory by default.
  local wsl_domains = wezterm.default_wsl_domains()
  for _, domain in ipairs(wsl_domains) do
    domain.default_cwd = '~'
  end
  config.wsl_domains = wsl_domains
  if #wsl_domains > 0 then
    config.default_domain = wsl_domains[1].name
  end
end

-- ============================================================
-- LOCAL OVERRIDES
-- ============================================================

-- wezterm_local.lua in the config directory may return a function that
-- receives (config, wezterm). A missing file is not an error.
local ok, result = pcall(require, 'wezterm_local')
if ok and type(result) == 'function' then
  result(config, wezterm)
elseif not ok and not tostring(result):find("module 'wezterm_local' not found", 1, true) then
  wezterm.log_error('wezterm_local.lua: ' .. tostring(result))
end

return config
