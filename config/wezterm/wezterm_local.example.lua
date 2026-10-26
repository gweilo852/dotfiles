-- Copy to ~/.config/wezterm/wezterm_local.lua (macOS, Linux) or
-- %USERPROFILE%\wezterm_local.lua (Windows) and edit. Not managed.
return function(config, wezterm)
  -- Larger or smaller text on this machine.
  -- config.font_size = 12.0

  -- Lighter font weight: 'Regular' or 'Medium'. Heavier: 'Bold'.
  -- config.font = wezterm.font('CaskaydiaMono Nerd Font Mono', { weight = 'Regular' })

  -- Dim all text a little more (1.0 = unchanged).
  -- config.foreground_text_hsb = { hue = 1.0, saturation = 1.0, brightness = 0.9 }

  -- Windows: start PowerShell instead of WSL.
  -- config.default_domain = 'local'
  -- config.default_prog = { 'pwsh.exe' }
end
