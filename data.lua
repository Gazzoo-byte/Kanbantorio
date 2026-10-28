data:extend({
  {
    type = "custom-input",
    name = "kanbantorio-toggle-ui",
    key_sequence = "CONTROL + K",
    consuming = "none"
  },
  {
    type = "custom-input",
    name = "kanbantorio-mouse-down",
    key_sequence = "mouse-button-1",
    consuming = "none"
  },
  {
    type = "shortcut",
    name = "kanbantorio-shortcut",
    order = "c[toggles]-z[kanbantorio]",
    action = "lua",
    localised_name = {"kanbantorio.shortcut-tooltip"},
    associated_control_input = "kanbantorio-toggle-ui",
    toggleable = true,
    icon = "__base__/graphics/icons/shortcut-toolbar/mip/new-blueprint-book-x56.png",
    icon_size = 56,
    small_icon = "__base__/graphics/icons/shortcut-toolbar/mip/new-blueprint-book-x24.png",
    small_icon_size = 24
  },
  {
    type = "item-with-tags",
    name = "kanbantorio-task-item",
    icon = "__base__/graphics/icons/shortcut-toolbar/mip/new-blueprint-book-x56.png",
    icon_size = 56,
    flags = {"only-in-cursor", "not-stackable", "spawnable"},
    hidden = true,
    auto_recycle = false,
    draw_label_for_cursor_render = true,
    stack_size = 1
  }
})

local styles = data.raw["gui-style"].default

styles.kanbantorio_column_frame = {
  type = "frame_style",
  parent = "inside_deep_frame",
  vertically_stretchable = "on",
  horizontally_stretchable = "on",
  minimal_width = 330,
  maximal_width = 420,
  padding = 0
}

styles.kanbantorio_column_frame_pinned = {
  type = "frame_style",
  parent = "inside_deep_frame",
  vertically_stretchable = "on",
  horizontally_stretchable = "on",
  minimal_width = 240,
  maximal_width = 300,
  padding = 0
}

styles.kanbantorio_column_scroll = {
  type = "scroll_pane_style",
  parent = "scroll_pane_in_shallow_frame",
  vertically_stretchable = "on",
  horizontally_stretchable = "on",
  padding = 8,
  extra_padding_when_activated = 0
}

styles.kanbantorio_card_frame = {
  type = "frame_style",
  parent = "inside_shallow_frame",
  horizontally_stretchable = "on",
  padding = 8,
  bottom_margin = 8
}

styles.kanbantorio_card_frame_pinned = {
  type = "frame_style",
  parent = "inside_shallow_frame",
  horizontally_stretchable = "on",
  padding = 6,
  bottom_margin = 6
}

styles.kanbantorio_card_frame_dragging = {
  type = "frame_style",
  parent = "inside_shallow_frame",
  horizontally_stretchable = "on",
  padding = 8,
  bottom_margin = 8
}

styles.kanbantorio_card_drag_button = {
  type = "button_style",
  parent = "list_box_item",
  horizontally_stretchable = "on",
  horizontally_squashable = "off",
  horizontal_align = "left",
  font = "default-semibold",
  default_font_color = {255, 230, 192},
  hovered_font_color = {255, 255, 255},
  clicked_font_color = {255, 230, 192},
  height = 28,
  left_padding = 6,
  right_padding = 6
}

styles.kanbantorio_card_drag_button_active = {
  type = "button_style",
  parent = "kanbantorio_card_drag_button",
  default_font_color = {255, 190, 90},
  hovered_font_color = {255, 210, 120}
}

styles.kanbantorio_card_title = {
  type = "label_style",
  parent = "caption_label",
  single_line = false,
  maximal_width = 230
}

styles.kanbantorio_card_description = {
  type = "label_style",
  parent = "label",
  single_line = false,
  horizontally_stretchable = "on",
  maximal_width = 290,
  font_color = {215, 215, 215}
}

styles.kanbantorio_card_description_pinned = {
  type = "label_style",
  parent = "label",
  single_line = false,
  horizontally_stretchable = "on",
  maximal_width = 220,
  font_color = {215, 215, 215}
}

styles.kanbantorio_muted_label = {
  type = "label_style",
  parent = "label",
  font_color = {160, 160, 160}
}

styles.kanbantorio_priority_high = {
  type = "label_style",
  parent = "bold_label",
  font_color = {255, 110, 110}
}

styles.kanbantorio_priority_normal = {
  type = "label_style",
  parent = "label",
  font_color = {130, 200, 255}
}

styles.kanbantorio_priority_low = {
  type = "label_style",
  parent = "label",
  font_color = {165, 215, 150}
}

styles.kanbantorio_small_button = {
  type = "button_style",
  parent = "button",
  font = "default-small-bold",
  height = 24,
  minimal_width = 32,
  horizontally_squashable = "off",
  top_padding = 0,
  bottom_padding = 0,
  left_padding = 8,
  right_padding = 8
}

styles.kanbantorio_bp_slot_button = {
  type = "button_style",
  parent = "slot_button",
  size = 36
}
