local mod_gui = require("mod-gui")
local storage_mod = require("scripts.storage")

local M = {}

local MAIN_FRAME_NAME = "kanbantorio_main_frame"
local OUTSIDE_CATCHER_NAME = "kanbantorio_outside_catcher"
local DRAG_PULSE_NAME = "kanbantorio_drag_pulse"
local TASK_MODAL_NAME = "kanbantorio_task_modal"
local VIEW_MODAL_NAME = "kanbantorio_view_modal"
local BP_MODAL_NAME = "kanbantorio_bp_modal"
local TOP_BUTTON_NAME = "kanbantorio_top_button"

function M.give_drag_cursor_item(player, task)
  if not (player and player.valid and task) then return end
  local stack = player.cursor_stack
  if not stack then return end
  -- Only put the drag indicator in cursor if the player isn't already holding another item
  if stack.valid_for_read and stack.name ~= "kanbantorio-task-item" then
    return
  end
  if not (player.cursor_record and player.cursor_record.valid) then
    pcall(function()
      stack.set_stack({ name = "kanbantorio-task-item", count = 1 })
      stack.label = "#" .. task.id .. " " .. task.title
      player.cursor_stack_temporary = true
    end)
  end
end

function M.clear_drag_cursor_item(player)
  if not (player and player.valid) then return end
  local stack = player.cursor_stack
  if stack and stack.valid_for_read and stack.name == "kanbantorio-task-item" then
    stack.clear()
  end
end

function M.activate_drag_visuals(player, task, handle_element)
  if not (player and player.valid and task) then return end

  if handle_element and handle_element.valid then
    handle_element.style = "kanbantorio_card_drag_button_active"
    handle_element.caption = "⇄ [Dragging] #" .. task.id .. " " .. task.title
  end

  local frame = player.gui.screen[MAIN_FRAME_NAME]
  if not frame then return end
  local titlebar = frame.kanbantorio_titlebar
  if titlebar and titlebar.kanbantorio_cancel_drag_btn then
    titlebar.kanbantorio_cancel_drag_btn.visible = true
  end
end

--- Destroys and recreates a tiny off-screen element while a hold-and-drag is active
--- so Factorio's GUI engine marks widgetUnderMouseNeedsUpdate = true on every tick,
--- ensuring mouse release fires on_gui_hover immediately even if the mouse is stationary.
function M.pulse_drag_hover_refresh(player)
  if not (player and player.valid) then return end
  if player.gui.screen[DRAG_PULSE_NAME] then
    player.gui.screen[DRAG_PULSE_NAME].destroy()
  end
  local pulse = player.gui.screen.add({
    type = "empty-widget",
    name = DRAG_PULSE_NAME,
    ignored_by_interaction = true
  })
  pulse.location = { x = -100, y = -100 }
  pulse.style.width = 1
  pulse.style.height = 1
end

function M.set_outside_catcher_active(player, active)
  if not (player and player.valid) then return end
  local catcher = player.gui.screen[OUTSIDE_CATCHER_NAME]
  local frame = player.gui.screen[MAIN_FRAME_NAME]
  if active and frame then
    if not catcher then
      catcher = player.gui.screen.add({
        type = "empty-widget",
        name = OUTSIDE_CATCHER_NAME,
        visible = true,
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_outside_drop",
          hover_type = "outside"
        }
      })
      catcher.location = { x = 0, y = 0 }
      catcher.style.width = 10000
      catcher.style.height = 10000
    else
      catcher.visible = true
    end
    frame.bring_to_front()
  else
    if catcher then
      catcher.visible = false
    end
    if player.gui.screen[DRAG_PULSE_NAME] then
      player.gui.screen[DRAG_PULSE_NAME].destroy()
    end
  end
end

function M.ensure_top_button(player)
  if not (player and player.valid) then return end
  local button_flow = mod_gui.get_button_flow(player)
  if not button_flow[TOP_BUTTON_NAME] then
    button_flow.add({
      type = "button",
      name = TOP_BUTTON_NAME,
      caption = {"kanbantorio.mod-button-caption"},
      tooltip = {"kanbantorio.mod-button-tooltip"},
      style = mod_gui.button_style
    })
  end
end

function M.sync_shortcut_state(player)
  if not (player and player.valid) then return end
  local is_open = player.gui.screen[MAIN_FRAME_NAME] ~= nil
  pcall(function()
    player.set_shortcut_toggled("kanbantorio-shortcut", is_open)
  end)
end

function M.is_open(player)
  return player and player.valid and player.gui.screen[MAIN_FRAME_NAME] ~= nil
end

function M.close_main_window(player)
  if not (player and player.valid) then return end
  local pstate = storage_mod.get_player_state(player)
  pstate.dragging_task_id = nil
  pstate.press_drag_task_id = nil
  pstate.left_handle = false

  M.clear_drag_cursor_item(player)
  if player.gui.screen[DRAG_PULSE_NAME] then
    player.gui.screen[DRAG_PULSE_NAME].destroy()
  end
  if player.gui.screen[OUTSIDE_CATCHER_NAME] then
    player.gui.screen[OUTSIDE_CATCHER_NAME].destroy()
  end
  if player.gui.screen[BP_MODAL_NAME] then
    player.gui.screen[BP_MODAL_NAME].destroy()
  end
  if player.gui.screen[TASK_MODAL_NAME] then
    player.gui.screen[TASK_MODAL_NAME].destroy()
  end
  if player.gui.screen[MAIN_FRAME_NAME] then
    player.gui.screen[MAIN_FRAME_NAME].destroy()
  end
  M.sync_shortcut_state(player)
end

function M.toggle_main_window(player)
  if M.is_open(player) then
    M.close_main_window(player)
  else
    M.open_main_window(player)
  end
end

--- Builds the assignee dropdown items ordered as:
--- "Unassigned", <current player>, <everyone else on force>
local function build_assignee_dropdown_data(player, current_assignee)
  local items = { {"kanbantorio.unassigned"} }
  local values = { "" }
  local selected_idx = 1

  local names = storage_mod.get_ordered_assignee_names(player, current_assignee)
  for _, name in ipairs(names) do
    table.insert(items, name)
    table.insert(values, name)
    if current_assignee and current_assignee == name then
      selected_idx = #values
    end
  end

  return items, values, selected_idx
end

--- Builds the filter assignee dropdown items for the board toolbar.
local function build_assignee_filter_data(player, current_filter)
  local items = {
    {"kanbantorio.filter-all-players"},
    {"kanbantorio.filter-assigned-to-me"},
    {"kanbantorio.filter-unassigned"}
  }
  local values = {
    "__all__",
    "__me__",
    "__unassigned__"
  }
  local selected_idx = 1

  local names = storage_mod.get_ordered_assignee_names(player)
  for _, name in ipairs(names) do
    table.insert(items, name)
    table.insert(values, name)
  end

  for i, val in ipairs(values) do
    if val == current_filter then
      selected_idx = i
      break
    end
  end

  return items, values, selected_idx
end

--- Renders a single task card inside a column scroll-pane.
local function render_task_card(parent, player, task, surface_filter, dragging_task_id, is_pinned)
  local is_being_dragged = (dragging_task_id == task.id)
  local card_style = is_being_dragged and "kanbantorio_card_frame_dragging"
    or (is_pinned and "kanbantorio_card_frame_pinned" or "kanbantorio_card_frame")

  local card = parent.add({
    type = "frame",
    style = card_style,
    direction = "vertical",
    raise_hover_events = true,
    tags = {
      action = "kanbantorio_drop_target",
      hover_type = "card",
      task_id = task.id,
      col_id = task.status
    }
  })

  -- Header row: Draggable Handle Button + Priority + Edit button
  local header = card.add({
    type = "flow",
    direction = "horizontal",
    raise_hover_events = true,
    tags = {
      action = "kanbantorio_drop_target",
      hover_type = "card",
      task_id = task.id,
      col_id = task.status
    }
  })
  header.style.horizontally_stretchable = true
  header.style.vertical_align = "center"

  local drag_btn = header.add({
    type = "button",
    caption = "⠿ #" .. task.id .. " " .. task.title,
    tooltip = {"kanbantorio.drag-handle-tooltip"},
    style = is_being_dragged and "kanbantorio_card_drag_button_active" or "kanbantorio_card_drag_button",
    raise_hover_events = true,
    tags = {
      action = "kanbantorio_card_drag_handle",
      hover_type = "card_handle",
      task_id = task.id,
      col_id = task.status
    }
  })
  drag_btn.style.horizontally_stretchable = true

  local prio_idx = storage_mod.PRIORITY_INDEX[task.priority or "normal"] or 2
  local prio_info = storage_mod.PRIORITIES[prio_idx]
  header.add({
    type = "label",
    caption = {"", "[", prio_info.caption, "]"},
    style = prio_info.style,
    raise_hover_events = true,
    tags = {
      action = "kanbantorio_drop_target",
      hover_type = "card",
      task_id = task.id,
      col_id = task.status
    }
  })

  if not is_pinned then
    local edit_btn = header.add({
      type = "sprite-button",
      sprite = "utility/rename_icon",
      tooltip = {"kanbantorio.edit-task-tooltip"},
      style = "tool_button",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_open_edit_modal",
        hover_type = "control",
        task_id = task.id,
        col_id = task.status
      }
    })
    edit_btn.style.size = { 28, 28 }
  end

  -- If viewing All Surfaces, show the surface badge on the card
  if surface_filter == storage_mod.ALL_SURFACES_KEY then
    local surf_row = card.add({
      type = "flow",
      direction = "horizontal",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })
    surf_row.style.top_margin = 2
    surf_row.add({
      type = "label",
      caption = storage_mod.get_surface_display_caption(task.surface_name or "nauvis"),
      style = "kanbantorio_muted_label",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })
    local surf_spacer = surf_row.add({
      type = "empty-widget",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })
    surf_spacer.style.horizontally_stretchable = true
    surf_spacer.style.height = 18
  end

  -- Description
  if task.description and task.description ~= "" then
    local desc = card.add({
      type = "label",
      caption = task.description,
      style = is_pinned and "kanbantorio_card_description_pinned" or "kanbantorio_card_description",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })
    desc.style.top_margin = 4
  end

  -- Blueprints attachment bar
  local bps = task.blueprints or {}
  if not is_pinned or #bps > 0 then
    local bp_flow = card.add({
      type = "flow",
      direction = "horizontal",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })
    bp_flow.style.vertical_align = "center"
    bp_flow.style.top_margin = 6
    bp_flow.style.horizontal_spacing = 4

    bp_flow.add({
      type = "label",
      caption = {"kanbantorio.blueprints-header"},
      style = "kanbantorio_muted_label",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })

    for bp_idx, bp in ipairs(bps) do
      local sprite_name = "item/" .. (bp.item_name or "blueprint")
      if not helpers.is_valid_sprite_path(sprite_name) then
        sprite_name = "item/blueprint"
      end
      bp_flow.add({
        type = "sprite-button",
        sprite = sprite_name,
        tooltip = is_pinned
          and {"kanbantorio.bp-slot-readonly-tooltip", bp.label or "Blueprint"}
          or {"kanbantorio.bp-slot-tooltip", bp.label or "Blueprint"},
        style = "kanbantorio_bp_slot_button",
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_card_bp_click",
          hover_type = "control",
          task_id = task.id,
          bp_index = bp_idx,
          col_id = task.status
        }
      })
    end

    if not is_pinned then
      -- Drop / Attach Blueprint slot button
      bp_flow.add({
        type = "sprite-button",
        sprite = "utility/export_slot",
        tooltip = {"kanbantorio.bp-drop-slot-tooltip"},
        style = "kanbantorio_bp_slot_button",
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_card_bp_attach",
          hover_type = "control",
          task_id = task.id,
          col_id = task.status
        }
      })

      -- Explicit Import String button
      local import_btn = bp_flow.add({
        type = "sprite-button",
        sprite = "utility/import",
        tooltip = {"kanbantorio.bp-import-string-tooltip"},
        style = "tool_button",
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_open_bp_import_modal",
          hover_type = "control",
          task_id = task.id,
          target = "task",
          col_id = task.status
        }
      })
      import_btn.style.size = { 28, 28 }
    end

    local bp_spacer = bp_flow.add({
      type = "empty-widget",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })
    bp_spacer.style.horizontally_stretchable = true
    bp_spacer.style.height = 32
  end

  -- Footer row: Assignee Dropdown in normal mode, or Mark Complete button in bottom-right in pinned mode
  if is_pinned then
    local pinned_footer = card.add({
      type = "flow",
      direction = "horizontal",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })
    pinned_footer.style.horizontally_stretchable = true
    pinned_footer.style.vertical_align = "center"
    pinned_footer.style.top_margin = 4

    local pf_spacer = pinned_footer.add({
      type = "empty-widget",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })
    pf_spacer.style.horizontally_stretchable = true
    pf_spacer.style.height = 24

    pinned_footer.add({
      type = "button",
      caption = {"kanbantorio.mark-complete-button"},
      tooltip = {"kanbantorio.mark-complete-tooltip"},
      style = "kanbantorio_small_button",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_mark_complete",
        hover_type = "control",
        task_id = task.id,
        col_id = task.status
      }
    })
  else
    local footer = card.add({
      type = "flow",
      direction = "horizontal",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })
    footer.style.horizontally_stretchable = true
    footer.style.vertical_align = "center"
    footer.style.top_margin = 6
    footer.style.horizontal_spacing = 6

    footer.add({
      type = "label",
      caption = {"kanbantorio.field-assignee"},
      style = "kanbantorio_muted_label",
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_drop_target",
        hover_type = "card",
        task_id = task.id,
        col_id = task.status
      }
    })

    local items, values, selected_idx = build_assignee_dropdown_data(player, task.assignee)
    local assignee_dd = footer.add({
      type = "drop-down",
      items = items,
      selected_index = selected_idx,
      raise_hover_events = true,
      tags = {
        action = "kanbantorio_card_assignee_changed",
        hover_type = "control",
        task_id = task.id,
        assignee_values = values,
        col_id = task.status
      }
    })
    assignee_dd.style.horizontally_stretchable = true
    assignee_dd.style.minimal_width = 140
  end
end

--- Checks if a task matches the current board filters.
local function task_matches_filters(task, player, pstate)
  local sfilter = pstate.selected_surface or storage_mod.ALL_SURFACES_KEY
  if sfilter ~= storage_mod.ALL_SURFACES_KEY then
    if (task.surface_name or "nauvis") ~= sfilter then
      return false
    end
  end

  if pstate.is_pinned then
    if task.assignee ~= player.name then
      return false
    end
  else
    local afilter = pstate.assignee_filter or "__all__"
    if afilter == "__me__" then
      if task.assignee ~= player.name then return false end
    elseif afilter == "__unassigned__" then
      if task.assignee and task.assignee ~= "" then return false end
    elseif afilter ~= "__all__" then
      if task.assignee ~= afilter then return false end
    end
  end

  local query = (pstate.search_query or ""):lower():match("^%s*(.-)%s*$")
  if query ~= "" then
    local title_match = (task.title or ""):lower():find(query, 1, true)
    local desc_match = (task.description or ""):lower():find(query, 1, true)
    local id_match = ("#" .. tostring(task.id)):find(query, 1, true)
    if not (title_match or desc_match or id_match) then
      return false
    end
  end

  return true
end

--- Populates or refreshes the 3 Kanban columns inside the board frame.
function M.refresh_board_columns(player)
  if not (player and player.valid) then return end
  local frame = player.gui.screen[MAIN_FRAME_NAME]
  if not frame then return end

  local pstate = storage_mod.get_player_state(player)
  local force_data = storage_mod.get_force_data(player.force)
  local is_pinned = (pstate.is_pinned == true)

  -- Adjust main frame dimensions for compact pinned mode vs full board mode
  if is_pinned then
    frame.style.minimal_width = 510
    frame.style.minimal_height = 360
    frame.style.maximal_height = 540
  else
    frame.style.minimal_width = 1040
    frame.style.minimal_height = 640
    frame.style.maximal_height = 860
  end

  -- Refresh surface dropdown items & selection, and toggle pinned-mode toolbar controls
  local toolbar = frame.kanbantorio_Subheader
  if toolbar then
    local surf_dd = toolbar.kanbantorio_surface_dropdown
    if surf_dd then
      local entries = storage_mod.get_surface_entries(player.force, true)
      local items = {}
      local keys = {}
      local selected_idx = 1
      for i, entry in ipairs(entries) do
        table.insert(items, entry.caption)
        table.insert(keys, entry.key)
        if entry.key == pstate.selected_surface then
          selected_idx = i
        end
      end
      pstate.selected_surface = keys[selected_idx] or storage_mod.ALL_SURFACES_KEY
      surf_dd.items = items
      surf_dd.selected_index = selected_idx
      surf_dd.style.minimal_width = is_pinned and 140 or 180
      surf_dd.tags = { action = "kanbantorio_surface_changed", hover_type = "window", surface_keys = keys }
    end

    if toolbar.kanbantorio_assignee_label then
      toolbar.kanbantorio_assignee_label.visible = not is_pinned
    end

    local assign_dd = toolbar.kanbantorio_assignee_filter
    if assign_dd then
      assign_dd.visible = not is_pinned
      if not is_pinned then
        local aitems, avalues, asel = build_assignee_filter_data(player, pstate.assignee_filter)
        assign_dd.items = aitems
        assign_dd.selected_index = asel
        assign_dd.tags = { action = "kanbantorio_assignee_filter_changed", hover_type = "window", filter_values = avalues }
      end
    end

    if toolbar.kanbantorio_search_field then
      toolbar.kanbantorio_search_field.style.width = is_pinned and 130 or 180
    end

    if toolbar.kanbantorio_new_task_btn then
      toolbar.kanbantorio_new_task_btn.visible = not is_pinned
    end
  end

  if frame.kanbantorio_quick_bar then
    frame.kanbantorio_quick_bar.visible = not is_pinned
  end

  -- Update titlebar pin button state and active drag status (zero layout shift)
  local titlebar = frame.kanbantorio_titlebar
  if titlebar then
    if titlebar.kanbantorio_pin_button then
      titlebar.kanbantorio_pin_button.toggled = is_pinned
    end

    local active_id = pstate.dragging_task_id or pstate.press_drag_task_id
    local dragged_task = active_id and storage_mod.find_task(player.force, active_id)
    if dragged_task then
      if titlebar.kanbantorio_cancel_drag_btn then
        titlebar.kanbantorio_cancel_drag_btn.visible = true
      end
      M.set_outside_catcher_active(player, true)
    else
      pstate.dragging_task_id = nil
      pstate.press_drag_task_id = nil
      pstate.left_handle = false
      if titlebar.kanbantorio_cancel_drag_btn then
        titlebar.kanbantorio_cancel_drag_btn.visible = false
      end
      M.set_outside_catcher_active(player, false)
      M.clear_drag_cursor_item(player)
    end
  end

  local columns_flow = frame.kanbantorio_columns_flow
  if not columns_flow then return end
  columns_flow.clear()

  local tasks_by_col = {
    todo = {},
    in_progress = {},
    done = {}
  }

  for _, task in ipairs(force_data.tasks) do
    if task_matches_filters(task, player, pstate) then
      local bucket = tasks_by_col[task.status] or tasks_by_col.todo
      table.insert(bucket, task)
    end
  end

  for _, col in ipairs(storage_mod.COLUMNS) do
    if not (is_pinned and col.id == "done") then
      local col_tasks = tasks_by_col[col.id] or {}

      local col_frame = columns_flow.add({
        type = "frame",
        style = is_pinned and "kanbantorio_column_frame_pinned" or "kanbantorio_column_frame",
        direction = "vertical",
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_drop_target",
          hover_type = "column",
          col_id = col.id
        }
      })

      -- Column header bar
      local col_header = col_frame.add({
        type = "frame",
        style = "subheader_frame",
        direction = "horizontal",
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_drop_target",
          hover_type = "column",
          col_id = col.id
        }
      })
      col_header.style.horizontally_stretchable = true
      col_header.style.left_padding = 10
      col_header.style.right_padding = 8

      col_header.add({
        type = "label",
        caption = {"", col.caption, " (" .. #col_tasks .. ")"},
        style = "subheader_caption_label",
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_drop_target",
          hover_type = "column",
          col_id = col.id
        }
      })

      local hspacer = col_header.add({
        type = "empty-widget",
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_drop_target",
          hover_type = "column",
          col_id = col.id
        }
      })
      hspacer.style.horizontally_stretchable = true
      hspacer.style.height = 28

      if col.id == "done" and #col_tasks > 0 and not is_pinned then
        col_header.add({
          type = "button",
          caption = {"kanbantorio.clear-done-button"},
          tooltip = {"kanbantorio.clear-done-tooltip"},
          style = "kanbantorio_small_button",
          raise_hover_events = true,
          tags = {
            action = "kanbantorio_clear_done",
            hover_type = "control",
            col_id = col.id
          }
        })
      end

      local scroll = col_frame.add({
        type = "scroll-pane",
        style = "kanbantorio_column_scroll",
        direction = "vertical",
        horizontal_scroll_policy = "never",
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_drop_target",
          hover_type = "column",
          col_id = col.id
        }
      })

      if #col_tasks == 0 then
        local empty_lbl = scroll.add({
          type = "label",
          caption = {"kanbantorio.empty-column"},
          style = "kanbantorio_muted_label",
          raise_hover_events = true,
          tags = {
            action = "kanbantorio_drop_target",
            hover_type = "column",
            col_id = col.id
          }
        })
        empty_lbl.style.top_margin = 8
        empty_lbl.style.single_line = false
        empty_lbl.style.maximal_width = is_pinned and 215 or 300
      else
        for _, task in ipairs(col_tasks) do
          render_task_card(scroll, player, task, pstate.selected_surface, pstate.dragging_task_id, is_pinned)
        end
      end

      -- Full-column stretchy leaf drop zone so dropping anywhere in the column works immediately
      local drop_zone = scroll.add({
        type = "empty-widget",
        raise_hover_events = true,
        tags = {
          action = "kanbantorio_drop_target",
          hover_type = "column",
          col_id = col.id
        }
      })
      drop_zone.style.horizontally_stretchable = true
      drop_zone.style.vertically_stretchable = true
      drop_zone.style.minimal_height = is_pinned and 220 or 500
    end
  end
end

function M.refresh_force_boards(force)
  if not (force and force.valid) then return end
  for _, p in pairs(force.players) do
    if p.valid then
      if M.is_open(p) then
        M.refresh_board_columns(p)
      end
      local view_modal = p.gui.screen[VIEW_MODAL_NAME]
      if view_modal and view_modal.valid then
        local vtask_id = view_modal.tags and view_modal.tags.task_id
        if vtask_id then
          if storage_mod.find_task(force, vtask_id) then
            M.open_task_view_modal(p, vtask_id)
          else
            view_modal.destroy()
          end
        end
      end
      local edit_modal = p.gui.screen[TASK_MODAL_NAME]
      if edit_modal and edit_modal.valid then
        local pstate = storage_mod.get_player_state(p)
        if pstate.editing_task_id and not storage_mod.find_task(force, pstate.editing_task_id) then
          pstate.editing_task_id = nil
          pstate.modal_draft_bps = nil
          edit_modal.destroy()
        end
      end
    end
  end
end

function M.open_main_window(player)
  if not (player and player.valid) then return end
  if player.gui.screen[MAIN_FRAME_NAME] then
    player.gui.screen[MAIN_FRAME_NAME].destroy()
  end

  local pstate = storage_mod.get_player_state(player)
  if not pstate.selected_surface then
    pstate.selected_surface = (player.surface and player.surface.valid) and player.surface.name or "nauvis"
  end
  pstate.hovered_in_window = true

  local frame = player.gui.screen.add({
    type = "frame",
    name = MAIN_FRAME_NAME,
    direction = "vertical",
    raise_hover_events = true,
    tags = { hover_type = "window" }
  })
  frame.style.minimal_width = 1040
  frame.style.minimal_height = 640
  frame.style.maximal_height = 860
  frame.auto_center = true

  -- Titlebar
  local titlebar = frame.add({
    type = "flow",
    name = "kanbantorio_titlebar",
    direction = "horizontal",
    raise_hover_events = true,
    tags = { hover_type = "window" }
  })
  titlebar.style.vertical_align = "center"
  titlebar.drag_target = frame

  titlebar.add({
    type = "label",
    name = "kanbantorio_window_title_label",
    caption = {"kanbantorio.window-title"},
    style = "frame_title",
    ignored_by_interaction = true
  })

  local drag_space = titlebar.add({
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  })
  drag_space.style.horizontally_stretchable = true
  drag_space.style.height = 24

  local cancel_drag_btn = titlebar.add({
    type = "button",
    name = "kanbantorio_cancel_drag_btn",
    caption = {"kanbantorio.cancel-drag-button"},
    style = "kanbantorio_small_button",
    visible = false,
    raise_hover_events = true,
    tags = { action = "kanbantorio_cancel_drag", hover_type = "window" }
  })
  cancel_drag_btn.style.right_margin = 6

  titlebar.add({
    type = "sprite-button",
    name = "kanbantorio_pin_button",
    sprite = "utility/track_button_white",
    hovered_sprite = "utility/track_button",
    clicked_sprite = "utility/track_button",
    style = "frame_action_button",
    tooltip = {"kanbantorio.pin-button-tooltip"},
    toggled = (pstate.is_pinned == true),
    raise_hover_events = true,
    tags = { action = "kanbantorio_toggle_pin", hover_type = "window" }
  })

  titlebar.add({
    type = "sprite-button",
    sprite = "utility/close",
    style = "frame_action_button",
    raise_hover_events = true,
    tags = { action = "kanbantorio_close_main", hover_type = "window" }
  })

  -- Toolbar / Subheader
  local toolbar = frame.add({
    type = "frame",
    name = "kanbantorio_Subheader",
    style = "subheader_frame",
    direction = "horizontal",
    raise_hover_events = true,
    tags = { hover_type = "window" }
  })
  toolbar.style.horizontally_stretchable = true
  toolbar.style.left_padding = 8
  toolbar.style.right_padding = 8

  toolbar.add({
    type = "label",
    caption = {"kanbantorio.surface-label"},
    style = "caption_label"
  })

  local surf_dd = toolbar.add({
    type = "drop-down",
    name = "kanbantorio_surface_dropdown",
    raise_hover_events = true
  })
  surf_dd.style.minimal_width = 180
  surf_dd.style.left_margin = 4

  local assign_lbl = toolbar.add({
    type = "label",
    name = "kanbantorio_assignee_label",
    caption = {"kanbantorio.assignee-filter-label"},
    style = "caption_label"
  })
  assign_lbl.style.left_margin = 8

  local assign_dd = toolbar.add({
    type = "drop-down",
    name = "kanbantorio_assignee_filter",
    raise_hover_events = true
  })
  assign_dd.style.minimal_width = 140
  assign_dd.style.left_margin = 4

  local search_box = toolbar.add({
    type = "textfield",
    name = "kanbantorio_search_field",
    text = pstate.search_query or "",
    icon_selector = true,
    raise_hover_events = true,
    tags = { action = "kanbantorio_search_changed", hover_type = "window" }
  })
  search_box.style.width = 180
  search_box.style.left_margin = 8
  search_box.tooltip = {"kanbantorio.search-placeholder"}

  local tb_spacer = toolbar.add({ type = "empty-widget" })
  tb_spacer.style.horizontally_stretchable = true

  toolbar.add({
    type = "button",
    name = "kanbantorio_new_task_btn",
    caption = {"kanbantorio.new-task-button"},
    style = "confirm_button",
    raise_hover_events = true,
    tags = { action = "kanbantorio_open_create_modal", hover_type = "window" }
  })

  -- Quick-Add row
  local quick_bar = frame.add({
    type = "flow",
    name = "kanbantorio_quick_bar",
    direction = "horizontal",
    raise_hover_events = true,
    tags = { hover_type = "window" }
  })
  quick_bar.style.horizontally_stretchable = true
  quick_bar.style.vertical_align = "center"
  quick_bar.style.top_margin = 6
  quick_bar.style.bottom_margin = 6
  quick_bar.style.horizontal_spacing = 6

  local quick_field = quick_bar.add({
    type = "textfield",
    name = "kanbantorio_quick_add_field",
    icon_selector = true,
    raise_hover_events = true,
    tags = { action = "kanbantorio_quick_add_confirm", hover_type = "window" }
  })
  quick_field.style.horizontally_stretchable = true
  quick_field.tooltip = {"kanbantorio.quick-add-placeholder"}

  quick_bar.add({
    type = "button",
    caption = {"kanbantorio.quick-add-button"},
    raise_hover_events = true,
    tags = { action = "kanbantorio_quick_add_click", hover_type = "window" }
  })

  -- 3 Columns Container
  local columns_flow = frame.add({
    type = "flow",
    name = "kanbantorio_columns_flow",
    direction = "horizontal",
    raise_hover_events = true,
    tags = { hover_type = "window" }
  })
  columns_flow.style.horizontally_stretchable = true
  columns_flow.style.vertically_stretchable = true
  columns_flow.style.horizontal_spacing = 8

  M.refresh_board_columns(player)
  M.sync_shortcut_state(player)
end

--- Renders the attached blueprint list inside the Create/Edit Task modal.
function M.refresh_modal_blueprints(player)
  local modal = player.gui.screen[TASK_MODAL_NAME]
  if not modal then return end
  local container = modal.kanbantorio_modal_body and modal.kanbantorio_modal_body.kanbantorio_modal_bp_list
  if not container then return end
  container.clear()

  local pstate = storage_mod.get_player_state(player)
  local bps = pstate.modal_draft_bps or {}

  local slots_flow = container.add({
    type = "flow",
    direction = "horizontal"
  })
  slots_flow.style.vertical_align = "center"
  slots_flow.style.horizontal_spacing = 6

  for i, bp in ipairs(bps) do
    local sprite_name = "item/" .. (bp.item_name or "blueprint")
    if not helpers.is_valid_sprite_path(sprite_name) then
      sprite_name = "item/blueprint"
    end
    slots_flow.add({
      type = "sprite-button",
      sprite = sprite_name,
      tooltip = {"kanbantorio.bp-slot-tooltip", bp.label or "Blueprint"},
      style = "kanbantorio_bp_slot_button",
      tags = {
        action = "kanbantorio_modal_bp_click",
        bp_index = i
      }
    })
  end

  slots_flow.add({
    type = "button",
    caption = {"kanbantorio.drop-bp-button"},
    tooltip = {"kanbantorio.bp-drop-slot-tooltip"},
    tags = { action = "kanbantorio_modal_bp_drop" }
  })

  slots_flow.add({
    type = "button",
    caption = {"kanbantorio.import-bp-string-button"},
    tooltip = {"kanbantorio.bp-import-string-tooltip"},
    tags = {
      action = "kanbantorio_open_bp_import_modal",
      target = "modal"
    }
  })
end

--- Opens the Create or Edit Task modal.
function M.open_task_modal(player, task_id)
  if not (player and player.valid) then return end
  if player.gui.screen[VIEW_MODAL_NAME] then
    player.gui.screen[VIEW_MODAL_NAME].destroy()
  end
  if player.gui.screen[TASK_MODAL_NAME] then
    player.gui.screen[TASK_MODAL_NAME].destroy()
  end

  local pstate = storage_mod.get_player_state(player)
  local task = task_id and storage_mod.find_task(player.force, task_id) or nil
  pstate.editing_task_id = task and task.id or nil

  pstate.modal_draft_bps = {}
  if task and task.blueprints then
    for _, bp in ipairs(task.blueprints) do
      table.insert(pstate.modal_draft_bps, {
        id = bp.id,
        label = bp.label,
        item_name = bp.item_name,
        data = bp.data
      })
    end
  end

  local modal = player.gui.screen.add({
    type = "frame",
    name = TASK_MODAL_NAME,
    direction = "vertical"
  })
  modal.style.minimal_width = 460
  modal.auto_center = true

  -- Titlebar
  local titlebar = modal.add({
    type = "flow",
    direction = "horizontal"
  })
  titlebar.drag_target = modal

  titlebar.add({
    type = "label",
    caption = task and {"kanbantorio.modal-edit-title", task.id} or {"kanbantorio.modal-create-title"},
    style = "frame_title",
    ignored_by_interaction = true
  })

  local drag = titlebar.add({
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24

  titlebar.add({
    type = "sprite-button",
    sprite = "utility/close",
    style = "frame_action_button",
    tags = { action = "kanbantorio_close_task_modal" }
  })

  local body = modal.add({
    type = "frame",
    name = "kanbantorio_modal_body",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical"
  })
  body.style.horizontally_stretchable = true

  body.add({
    type = "label",
    caption = {"kanbantorio.field-title"},
    style = "caption_label"
  })
  local title_field = body.add({
    type = "textfield",
    name = "kanbantorio_modal_title",
    text = task and task.title or "",
    icon_selector = true
  })
  title_field.style.horizontally_stretchable = true
  title_field.focus()

  local desc_lbl = body.add({
    type = "label",
    caption = {"kanbantorio.field-description"},
    style = "caption_label"
  })
  desc_lbl.style.top_margin = 6

  local desc_box = body.add({
    type = "text-box",
    name = "kanbantorio_modal_description",
    text = task and task.description or "",
    icon_selector = true
  })
  desc_box.style.horizontally_stretchable = true
  desc_box.style.height = 80
  desc_box.word_wrap = true

  local grid = body.add({
    type = "table",
    name = "kanbantorio_modal_grid",
    column_count = 2
  })
  grid.style.top_margin = 8
  grid.style.horizontal_spacing = 12
  grid.style.vertical_spacing = 6

  -- 1. Surface selector
  grid.add({ type = "label", caption = {"kanbantorio.field-surface"}, style = "caption_label" })
  local surf_entries = storage_mod.get_surface_entries(player.force, false)
  local surf_items = {}
  local surf_keys = {}
  local default_surf = task and task.surface_name
    or (pstate.selected_surface ~= storage_mod.ALL_SURFACES_KEY and pstate.selected_surface)
    or ((player.surface and player.surface.valid) and player.surface.name or "nauvis")
  local surf_sel = 1
  for i, entry in ipairs(surf_entries) do
    table.insert(surf_items, entry.raw_caption)
    table.insert(surf_keys, entry.key)
    if entry.key == default_surf then
      surf_sel = i
    end
  end
  local modal_surf_dd = grid.add({
    type = "drop-down",
    name = "kanbantorio_modal_surface",
    items = surf_items,
    selected_index = surf_sel,
    tags = { surface_keys = surf_keys }
  })
  modal_surf_dd.style.minimal_width = 220

  -- 2. Column (Status) selector — defaults to "To Do" (index 1) for new tasks
  grid.add({ type = "label", caption = {"kanbantorio.field-status"}, style = "caption_label" })
  local col_items = {}
  local col_sel = 1
  for i, col in ipairs(storage_mod.COLUMNS) do
    table.insert(col_items, col.caption)
    if task and task.status == col.id then
      col_sel = i
    end
  end
  local modal_col_dd = grid.add({
    type = "drop-down",
    name = "kanbantorio_modal_status",
    items = col_items,
    selected_index = col_sel
  })
  modal_col_dd.style.minimal_width = 220

  -- 3. Assignee selector ("Unassigned, <current player>, <everyone else>")
  grid.add({ type = "label", caption = {"kanbantorio.field-assignee"}, style = "caption_label" })
  local aitems, avalues, asel = build_assignee_dropdown_data(player, task and task.assignee or nil)
  local modal_assign_dd = grid.add({
    type = "drop-down",
    name = "kanbantorio_modal_assignee",
    items = aitems,
    selected_index = asel,
    tags = { assignee_values = avalues }
  })
  modal_assign_dd.style.minimal_width = 220

  -- 4. Priority selector
  grid.add({ type = "label", caption = {"kanbantorio.field-priority"}, style = "caption_label" })
  local prio_items = {}
  local prio_sel = 2
  for i, p in ipairs(storage_mod.PRIORITIES) do
    table.insert(prio_items, p.caption)
    if task and task.priority == p.id then
      prio_sel = i
    end
  end
  local modal_prio_dd = grid.add({
    type = "drop-down",
    name = "kanbantorio_modal_priority",
    items = prio_items,
    selected_index = prio_sel
  })
  modal_prio_dd.style.minimal_width = 220

  local bp_lbl = body.add({
    type = "label",
    caption = {"kanbantorio.field-blueprints"},
    style = "caption_label"
  })
  bp_lbl.style.top_margin = 8

  body.add({
    type = "flow",
    name = "kanbantorio_modal_bp_list",
    direction = "vertical"
  })

  M.refresh_modal_blueprints(player)

  local footer = modal.add({
    type = "flow",
    direction = "horizontal"
  })
  footer.style.horizontally_stretchable = true
  footer.style.top_margin = 8
  footer.style.vertical_align = "center"

  footer.add({
    type = "button",
    caption = {"kanbantorio.cancel-button"},
    style = "back_button",
    tags = { action = "kanbantorio_close_task_modal" }
  })

  if task then
    local del_btn = footer.add({
      type = "button",
      caption = {"kanbantorio.delete-task-button"},
      tooltip = {"kanbantorio.delete-task-tooltip"},
      style = "red_button",
      tags = {
        action = "kanbantorio_delete_from_modal",
        task_id = task.id
      }
    })
    del_btn.style.left_margin = 8
  end

  local fspacer = footer.add({ type = "empty-widget" })
  fspacer.style.horizontally_stretchable = true

  footer.add({
    type = "button",
    caption = task and {"kanbantorio.save-button"} or {"kanbantorio.create-button"},
    style = "confirm_button",
    tags = { action = "kanbantorio_save_task_modal" }
  })
end

--- Opens the Read-Only Task View modal (used when clicking a shared task link in chat).
function M.open_task_view_modal(player, task_id)
  if not (player and player.valid) then return end
  local task = storage_mod.find_task(player.force, task_id)
  if not task then
    player.print({"kanbantorio.msg-task-not-found", tostring(task_id)})
    return
  end

  if player.gui.screen[VIEW_MODAL_NAME] then
    player.gui.screen[VIEW_MODAL_NAME].destroy()
  end

  local modal = player.gui.screen.add({
    type = "frame",
    name = VIEW_MODAL_NAME,
    direction = "vertical",
    tags = { task_id = task.id }
  })
  modal.style.minimal_width = 460
  modal.auto_center = true

  -- Titlebar
  local titlebar = modal.add({
    type = "flow",
    direction = "horizontal"
  })
  titlebar.drag_target = modal

  titlebar.add({
    type = "label",
    caption = {"kanbantorio.modal-view-title", task.id},
    style = "frame_title",
    ignored_by_interaction = true
  })

  local drag = titlebar.add({
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24

  titlebar.add({
    type = "sprite-button",
    sprite = "utility/close",
    style = "frame_action_button",
    tags = { action = "kanbantorio_close_view_modal" }
  })

  local body = modal.add({
    type = "frame",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical"
  })
  body.style.horizontally_stretchable = true

  -- Title (read-only textfield)
  body.add({
    type = "label",
    caption = {"kanbantorio.field-title"},
    style = "caption_label"
  })
  local title_field = body.add({
    type = "textfield",
    text = task.title or ""
  })
  title_field.style.horizontally_stretchable = true
  title_field.read_only = true

  -- Description (read-only text-box)
  local desc_lbl = body.add({
    type = "label",
    caption = {"kanbantorio.field-description"},
    style = "caption_label"
  })
  desc_lbl.style.top_margin = 6

  local desc_box = body.add({
    type = "text-box",
    text = task.description or ""
  })
  desc_box.style.horizontally_stretchable = true
  desc_box.style.height = 80
  desc_box.word_wrap = true
  desc_box.read_only = true

  -- Details Grid
  local grid = body.add({
    type = "table",
    column_count = 2
  })
  grid.style.top_margin = 8
  grid.style.horizontal_spacing = 12
  grid.style.vertical_spacing = 6

  -- Surface
  grid.add({ type = "label", caption = {"kanbantorio.field-surface"}, style = "caption_label" })
  grid.add({ type = "label", caption = storage_mod.get_surface_display_caption(task.surface_name or "nauvis") })

  -- Column
  local col_idx = storage_mod.COLUMN_INDEX[task.status] or 1
  local col_info = storage_mod.COLUMNS[col_idx]
  grid.add({ type = "label", caption = {"kanbantorio.field-status"}, style = "caption_label" })
  grid.add({ type = "label", caption = col_info and col_info.caption or {"kanbantorio.column-todo"} })

  -- Assignee
  grid.add({ type = "label", caption = {"kanbantorio.field-assignee"}, style = "caption_label" })
  grid.add({
    type = "label",
    caption = (task.assignee and task.assignee ~= "") and task.assignee or {"kanbantorio.unassigned"}
  })

  -- Priority
  local prio_idx = storage_mod.PRIORITY_INDEX[task.priority or "normal"] or 2
  local prio_info = storage_mod.PRIORITIES[prio_idx]
  grid.add({ type = "label", caption = {"kanbantorio.field-priority"}, style = "caption_label" })
  grid.add({ type = "label", caption = prio_info.caption, style = prio_info.style })

  -- Created by
  if task.created_by and task.created_by ~= "" then
    grid.add({ type = "label", caption = {"kanbantorio.field-created-by"}, style = "caption_label" })
    grid.add({ type = "label", caption = task.created_by })
  end

  -- Attached Blueprints
  local bp_lbl = body.add({
    type = "label",
    caption = {"kanbantorio.field-blueprints"},
    style = "caption_label"
  })
  bp_lbl.style.top_margin = 8

  local bps = task.blueprints or {}
  if #bps == 0 then
    body.add({
      type = "label",
      caption = {"kanbantorio.no-blueprints-attached"},
      style = "kanbantorio_muted_label"
    })
  else
    local slots_flow = body.add({
      type = "flow",
      direction = "horizontal"
    })
    slots_flow.style.vertical_align = "center"
    slots_flow.style.horizontal_spacing = 6
    slots_flow.style.top_margin = 4

    for bp_idx, bp in ipairs(bps) do
      local sprite_name = "item/" .. (bp.item_name or "blueprint")
      if not helpers.is_valid_sprite_path(sprite_name) then
        sprite_name = "item/blueprint"
      end
      slots_flow.add({
        type = "sprite-button",
        sprite = sprite_name,
        tooltip = {"kanbantorio.bp-slot-readonly-tooltip", bp.label or "Blueprint"},
        style = "kanbantorio_bp_slot_button",
        tags = {
          action = "kanbantorio_view_bp_click",
          task_id = task.id,
          bp_index = bp_idx
        }
      })
    end
  end

  -- Footer buttons: Close | Edit Task
  local footer = modal.add({
    type = "flow",
    direction = "horizontal"
  })
  footer.style.horizontally_stretchable = true
  footer.style.top_margin = 8
  footer.style.vertical_align = "center"

  footer.add({
    type = "button",
    caption = {"kanbantorio.close-button"},
    style = "back_button",
    tags = { action = "kanbantorio_close_view_modal" }
  })

  local fspacer = footer.add({ type = "empty-widget" })
  fspacer.style.horizontally_stretchable = true

  footer.add({
    type = "button",
    caption = {"kanbantorio.view-task-button"},
    style = "confirm_button",
    tags = { action = "kanbantorio_open_edit_modal", task_id = task.id }
  })
end

--- Opens the Blueprint String Import or Export/View Modal.
--- opts: { mode = "import" | "export", target = "task" | "modal" | "view", task_id = number?, bp_index = number? }
function M.open_bp_modal(player, opts)
  if not (player and player.valid) then return end
  if player.gui.screen[BP_MODAL_NAME] then
    player.gui.screen[BP_MODAL_NAME].destroy()
  end

  local is_export = (opts.mode == "export")
  local is_readonly = (opts.target == "view")
  local bp_entry = nil
  if is_export then
    if opts.target == "modal" then
      local pstate = storage_mod.get_player_state(player)
      bp_entry = pstate.modal_draft_bps and pstate.modal_draft_bps[opts.bp_index]
    else
      local task = storage_mod.find_task(player.force, opts.task_id)
      bp_entry = task and task.blueprints and task.blueprints[opts.bp_index]
    end
    if not bp_entry then return end
  end

  local modal = player.gui.screen.add({
    type = "frame",
    name = BP_MODAL_NAME,
    direction = "vertical"
  })
  modal.style.minimal_width = 480
  modal.auto_center = true

  local titlebar = modal.add({
    type = "flow",
    direction = "horizontal"
  })
  titlebar.drag_target = modal

  titlebar.add({
    type = "label",
    caption = is_export
      and {"kanbantorio.modal-bp-export-title", bp_entry.label or "Blueprint"}
      or {"kanbantorio.modal-bp-import-title"},
    style = "frame_title",
    ignored_by_interaction = true
  })

  local drag = titlebar.add({
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true
  })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24

  titlebar.add({
    type = "sprite-button",
    sprite = "utility/close",
    style = "frame_action_button",
    tags = { action = "kanbantorio_close_bp_modal" }
  })

  local body = modal.add({
    type = "frame",
    name = "kanbantorio_bp_modal_body",
    style = "inside_shallow_frame_with_padding",
    direction = "vertical"
  })
  body.style.horizontally_stretchable = true

  body.add({
    type = "label",
    caption = {"kanbantorio.bp-label-field"},
    style = "caption_label"
  })
  local label_field = body.add({
    type = "textfield",
    name = "kanbantorio_bp_label_input",
    text = is_export and (bp_entry.label or "") or "",
    icon_selector = true
  })
  label_field.style.horizontally_stretchable = true
  if is_readonly then
    label_field.read_only = true
  end

  local str_lbl = body.add({
    type = "label",
    caption = is_export and {"kanbantorio.bp-copy-hint"} or {"kanbantorio.bp-string-field"},
    style = "caption_label"
  })
  str_lbl.style.top_margin = 6

  local str_box = body.add({
    type = "text-box",
    name = "kanbantorio_bp_string_input",
    text = is_export and (bp_entry.data or "") or ""
  })
  str_box.style.horizontally_stretchable = true
  str_box.style.height = 140
  str_box.word_wrap = true
  if is_export then
    str_box.read_only = true
    str_box.focus()
    str_box.select_all()
  else
    str_box.focus()
  end

  local footer = modal.add({
    type = "flow",
    direction = "horizontal"
  })
  footer.style.horizontally_stretchable = true
  footer.style.top_margin = 8
  footer.style.vertical_align = "center"

  footer.add({
    type = "button",
    caption = is_readonly and {"kanbantorio.close-button"} or {"kanbantorio.cancel-button"},
    style = "back_button",
    tags = { action = "kanbantorio_close_bp_modal" }
  })

  local fspacer = footer.add({ type = "empty-widget" })
  fspacer.style.horizontally_stretchable = true

  if is_export and not is_readonly then
    footer.add({
      type = "button",
      caption = {"kanbantorio.bp-update-label"},
      style = "confirm_button",
      tags = {
        action = "kanbantorio_bp_update_label",
        target = opts.target,
        task_id = opts.task_id,
        bp_index = opts.bp_index
      }
    })
  elseif not is_export then
    footer.add({
      type = "button",
      caption = {"kanbantorio.bp-import-confirm"},
      style = "confirm_button",
      tags = {
        action = "kanbantorio_confirm_bp_import",
        target = opts.target,
        task_id = opts.task_id
      }
    })
  end
end

return M
