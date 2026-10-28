local storage_mod = require("scripts.storage")
local blueprints = require("scripts.blueprints")
local gui = require("scripts.gui")

local function init_all_players()
  storage_mod.ensure_storage()
  for _, player in pairs(game.players) do
    if player.valid then
      storage_mod.get_player_state(player)
      gui.ensure_top_button(player)
      gui.sync_shortcut_state(player)
    end
  end
end

script.on_init(function()
  init_all_players()
end)

script.on_configuration_changed(function()
  init_all_players()
  for _, force in pairs(game.forces) do
    if force.valid then
      gui.refresh_force_boards(force)
    end
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then
    storage_mod.get_player_state(player)
    gui.ensure_top_button(player)
    gui.sync_shortcut_state(player)
  end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then
    storage_mod.get_player_state(player)
    gui.ensure_top_button(player)
    gui.sync_shortcut_state(player)
    gui.refresh_force_boards(player.force)
  end
end)

script.on_event(defines.events.on_player_left_game, function(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then
    local pstate = storage_mod.get_player_state(player)
    pstate.dragging_task_id = nil
    pstate.press_drag_task_id = nil
    pstate.left_handle = false
    pstate.hovered_handle_task_id = nil
    gui.set_outside_catcher_active(player, false)
    gui.clear_drag_cursor_item(player)
  end
end)

script.on_event(defines.events.on_player_removed, function(event)
  if storage and storage.players then
    storage.players[event.player_index] = nil
  end
  for _, force in pairs(game.forces) do
    if force.valid then
      gui.refresh_force_boards(force)
    end
  end
end)

script.on_event(defines.events.on_player_changed_force, function(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then
    if gui.is_open(player) then
      gui.refresh_board_columns(player)
    end
    gui.refresh_force_boards(player.force)
  end
  if event.force and event.force.valid then
    gui.refresh_force_boards(event.force)
  end
end)

local function on_surfaces_updated()
  for _, force in pairs(game.forces) do
    if force.valid then
      gui.refresh_force_boards(force)
    end
  end
end

script.on_event({
  defines.events.on_surface_created,
  defines.events.on_surface_deleted,
  defines.events.on_surface_renamed,
  defines.events.on_surface_imported,
  defines.events.on_player_changed_surface
}, on_surfaces_updated)

script.on_event(defines.events.on_chunk_charted, function(event)
  if event.position and event.position.x == 0 and event.position.y == 0 then
    if event.force and event.force.valid then
      gui.refresh_force_boards(event.force)
    end
  end
end)

-- Share a task link to the force chat
local function share_task_in_chat(player, task_id)
  if not (player and player.valid) then return end
  local task = storage_mod.find_task(player.force, task_id)
  if not task then return end
  player.force.print({"kanbantorio.chat-task-shared", player.name, task.id, task.title})
end

-- Open Read-Only Task View when a player clicks a shared task GPS tag in chat
script.on_event(defines.events.on_player_clicked_gps_tag, function(event)
  local surface_str = event.surface
  if not surface_str then return end
  local task_id_str = surface_str:match("^kanbantorio%-task%-(%d+)$")
  if not task_id_str then return end

  local task_id = tonumber(task_id_str)
  if not task_id then return end

  local player = game.get_player(event.player_index)
  if player and player.valid then
    gui.open_task_view_modal(player, task_id)
  end
end)

-- Toggle UI via custom hotkey (Ctrl + K)
script.on_event("kanbantorio-toggle-ui", function(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then
    gui.toggle_main_window(player)
  end
end)

-- Mouse-button-1 press tracking for hold-and-drag
script.on_event("kanbantorio-mouse-down", function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid and gui.is_open(player)) then return end

  local pstate = storage_mod.get_player_state(player)

  -- Start hold-and-drag if pressing mouse-button-1 while hovering a card's drag handle
  if pstate.hovered_handle_task_id then
    local task = storage_mod.find_task(player.force, pstate.hovered_handle_task_id)
    if task then
      pstate.press_drag_task_id = task.id
      pstate.left_handle = false
      gui.set_outside_catcher_active(player, true)
      gui.activate_drag_visuals(player, task)
    end
  end
end)

-- Hover tracking for drag-and-drop across columns, cards, and outside-window drop catcher
script.on_event(defines.events.on_gui_hover, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local tags = element.tags
  local hover_type = tags and tags.hover_type
  if not hover_type then return end

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local pstate = storage_mod.get_player_state(player)

  -- If a hold-and-drag was in progress and left the origin handle,
  -- Factorio fires on_gui_hover on the destination widget at the exact moment mouse-button-1 is released.
  if pstate.press_drag_task_id and pstate.left_handle then
    local drag_id = pstate.press_drag_task_id
    pstate.press_drag_task_id = nil
    pstate.left_handle = false
    pstate.dragging_task_id = nil
    pstate.hovered_handle_task_id = (hover_type == "card_handle") and tags.task_id or nil
    gui.set_outside_catcher_active(player, false)
    gui.clear_drag_cursor_item(player)

    if hover_type == "outside" then
      share_task_in_chat(player, drag_id)
      gui.refresh_board_columns(player)
    elseif tags.col_id then
      storage_mod.move_task_to_target(player.force, drag_id, tags.col_id, tags.task_id)
      gui.refresh_force_boards(player.force)
    else
      gui.refresh_board_columns(player)
    end
    return
  end

  if hover_type == "card_handle" then
    pstate.hovered_handle_task_id = tags.task_id
  else
    pstate.hovered_handle_task_id = nil
  end
end)

script.on_event(defines.events.on_gui_leave, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local tags = element.tags
  local hover_type = tags and tags.hover_type
  if hover_type ~= "card_handle" then return end

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local pstate = storage_mod.get_player_state(player)

  if pstate.hovered_handle_task_id == tags.task_id then
    pstate.hovered_handle_task_id = nil
  end
  if pstate.press_drag_task_id == tags.task_id then
    pstate.left_handle = true
    local task = storage_mod.find_task(player.force, tags.task_id)
    if task then
      gui.activate_drag_visuals(player, task, element)
    end
  end
end)

-- While a hold-and-drag is active, pulse an off-screen element each tick so Factorio's
-- GUI engine immediately updates widgetUnderMouse on the exact tick mouse-button-1 is released,
-- even if the mouse cursor is completely stationary after releasing.
script.on_event(defines.events.on_tick, function()
  if not (storage and storage.players) then return end
  for player_index, pstate in pairs(storage.players) do
    if pstate.press_drag_task_id and pstate.left_handle then
      local player = game.get_player(player_index)
      if player and player.valid and gui.is_open(player) then
        gui.pulse_drag_hover_refresh(player)
      else
        pstate.press_drag_task_id = nil
        pstate.left_handle = false
      end
    end
  end
end)

-- Toggle UI via shortcut bar button
script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == "kanbantorio-shortcut" then
    local player = game.get_player(event.player_index)
    if player and player.valid then
      gui.toggle_main_window(player)
    end
  end
end)

local function handle_quick_add(player)
  local frame = player.gui.screen.kanbantorio_main_frame
  if not frame then return end
  local quick_bar = frame.kanbantorio_quick_bar
  if not (quick_bar and quick_bar.kanbantorio_quick_add_field) then return end

  local field = quick_bar.kanbantorio_quick_add_field
  local title = (field.text or ""):match("^%s*(.-)%s*$")
  if title == "" then
    player.print({"kanbantorio.msg-title-required"})
    return
  end

  local pstate = storage_mod.get_player_state(player)
  local surface_name = pstate.selected_surface
  if not surface_name or surface_name == storage_mod.ALL_SURFACES_KEY then
    surface_name = (player.surface and player.surface.valid) and player.surface.name or "nauvis"
  end

  storage_mod.create_task(player.force, {
    title = title,
    description = "",
    status = "todo",
    surface_name = surface_name,
    assignee = nil,
    priority = "normal",
    blueprints = {},
    created_by = player.name
  })

  field.text = ""
  gui.refresh_force_boards(player.force)
end

local function handle_save_task_modal(player)
  local modal = player.gui.screen.kanbantorio_task_modal
  if not modal then return end
  local body = modal.kanbantorio_modal_body
  if not body then return end

  local title = (body.kanbantorio_modal_title and body.kanbantorio_modal_title.text or ""):match("^%s*(.-)%s*$")
  if title == "" then
    player.print({"kanbantorio.msg-title-required"})
    return
  end

  local description = body.kanbantorio_modal_description and body.kanbantorio_modal_description.text or ""
  local grid = body.kanbantorio_modal_grid

  local surface_name = "nauvis"
  if grid and grid.kanbantorio_modal_surface then
    local sdd = grid.kanbantorio_modal_surface
    local skeys = sdd.tags and sdd.tags.surface_keys or {}
    surface_name = skeys[sdd.selected_index] or "nauvis"
  end

  local status = "todo"
  if grid and grid.kanbantorio_modal_status then
    local col = storage_mod.COLUMNS[grid.kanbantorio_modal_status.selected_index]
    status = col and col.id or "todo"
  end

  local assignee = nil
  if grid and grid.kanbantorio_modal_assignee then
    local add = grid.kanbantorio_modal_assignee
    local avals = add.tags and add.tags.assignee_values or {}
    local raw = avals[add.selected_index]
    if raw and raw ~= "" then
      assignee = raw
    end
  end

  local priority = "normal"
  if grid and grid.kanbantorio_modal_priority then
    local prio = storage_mod.PRIORITIES[grid.kanbantorio_modal_priority.selected_index]
    priority = prio and prio.id or "normal"
  end

  local pstate = storage_mod.get_player_state(player)
  local bps = pstate.modal_draft_bps or {}

  if pstate.editing_task_id then
    local task = storage_mod.find_task(player.force, pstate.editing_task_id)
    if task then
      task.title = title
      task.description = description
      task.surface_name = surface_name
      task.status = status
      task.assignee = assignee
      task.priority = priority
      task.blueprints = bps
    end
  else
    storage_mod.create_task(player.force, {
      title = title,
      description = description,
      status = status,
      surface_name = surface_name,
      assignee = assignee,
      priority = priority,
      blueprints = bps,
      created_by = player.name
    })
  end

  pstate.editing_task_id = nil
  pstate.modal_draft_bps = nil
  modal.destroy()
  gui.refresh_force_boards(player.force)
end

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if element.name == "kanbantorio_top_button" then
    gui.toggle_main_window(player)
    return
  end

  local tags = element.tags
  local action = tags and tags.action
  if not action then return end

  local pstate = storage_mod.get_player_state(player)

  if action == "kanbantorio_close_main" then
    gui.close_main_window(player)

  elseif action == "kanbantorio_toggle_pin" then
    pstate.is_pinned = not pstate.is_pinned
    if pstate.is_pinned then
      pstate.editing_task_id = nil
      pstate.modal_draft_bps = nil
      if player.gui.screen.kanbantorio_task_modal then
        player.gui.screen.kanbantorio_task_modal.destroy()
      end
      if player.gui.screen.kanbantorio_bp_modal then
        player.gui.screen.kanbantorio_bp_modal.destroy()
      end
    end
    gui.refresh_board_columns(player)

  elseif action == "kanbantorio_card_drag_handle" then
    -- In-place click on a card's drag handle: clear pending hold-drag and either drop or pick up
    pstate.press_drag_task_id = nil
    pstate.left_handle = false

    if pstate.dragging_task_id then
      local moving_id = pstate.dragging_task_id
      pstate.dragging_task_id = nil
      gui.set_outside_catcher_active(player, false)
      gui.clear_drag_cursor_item(player)
      if moving_id ~= tags.task_id then
        storage_mod.move_task_to_target(player.force, moving_id, tags.col_id, tags.task_id)
        gui.refresh_force_boards(player.force)
      else
        gui.refresh_board_columns(player)
      end
    else
      pstate.dragging_task_id = tags.task_id
      local task = storage_mod.find_task(player.force, tags.task_id)
      gui.give_drag_cursor_item(player, task)
      gui.set_outside_catcher_active(player, true)
      gui.refresh_board_columns(player)
    end

  elseif action == "kanbantorio_drop_target" then
    if pstate.dragging_task_id then
      local moving_id = pstate.dragging_task_id
      pstate.dragging_task_id = nil
      pstate.press_drag_task_id = nil
      pstate.left_handle = false
      gui.set_outside_catcher_active(player, false)
      gui.clear_drag_cursor_item(player)
      storage_mod.move_task_to_target(player.force, moving_id, tags.col_id, tags.task_id)
      gui.refresh_force_boards(player.force)
    end

  elseif action == "kanbantorio_outside_drop" then
    if pstate.dragging_task_id then
      local shared_id = pstate.dragging_task_id
      pstate.dragging_task_id = nil
      pstate.press_drag_task_id = nil
      pstate.left_handle = false
      gui.set_outside_catcher_active(player, false)
      gui.clear_drag_cursor_item(player)
      share_task_in_chat(player, shared_id)
      gui.refresh_board_columns(player)
    else
      pstate.press_drag_task_id = nil
      pstate.left_handle = false
      gui.set_outside_catcher_active(player, false)
      gui.clear_drag_cursor_item(player)
    end

  elseif action == "kanbantorio_cancel_drag" then
    pstate.dragging_task_id = nil
    pstate.press_drag_task_id = nil
    pstate.left_handle = false
    gui.set_outside_catcher_active(player, false)
    gui.clear_drag_cursor_item(player)
    gui.refresh_board_columns(player)

  elseif action == "kanbantorio_open_create_modal" then
    gui.open_task_modal(player, nil)

  elseif action == "kanbantorio_open_edit_modal" then
    gui.open_task_modal(player, tags.task_id)

  elseif action == "kanbantorio_close_view_modal" then
    if player.gui.screen.kanbantorio_view_modal then
      player.gui.screen.kanbantorio_view_modal.destroy()
    end

  elseif action == "kanbantorio_close_task_modal" then
    pstate.editing_task_id = nil
    pstate.modal_draft_bps = nil
    if player.gui.screen.kanbantorio_task_modal then
      player.gui.screen.kanbantorio_task_modal.destroy()
    end

  elseif action == "kanbantorio_save_task_modal" then
    handle_save_task_modal(player)

  elseif action == "kanbantorio_quick_add_click" then
    handle_quick_add(player)

  elseif action == "kanbantorio_mark_complete" then
    if pstate.dragging_task_id == tags.task_id then
      pstate.dragging_task_id = nil
      gui.set_outside_catcher_active(player, false)
      gui.clear_drag_cursor_item(player)
    end
    if pstate.press_drag_task_id == tags.task_id then
      pstate.press_drag_task_id = nil
      pstate.left_handle = false
      gui.set_outside_catcher_active(player, false)
      gui.clear_drag_cursor_item(player)
    end
    if storage_mod.move_task_to_target(player.force, tags.task_id, "done", nil) then
      gui.refresh_force_boards(player.force)
    end

  elseif action == "kanbantorio_delete_from_modal" or action == "kanbantorio_delete_task" then
    if pstate.dragging_task_id == tags.task_id then
      pstate.dragging_task_id = nil
    end
    if pstate.press_drag_task_id == tags.task_id then
      pstate.press_drag_task_id = nil
      pstate.left_handle = false
    end
    pstate.editing_task_id = nil
    pstate.modal_draft_bps = nil
    if player.gui.screen.kanbantorio_task_modal then
      player.gui.screen.kanbantorio_task_modal.destroy()
    end
    if storage_mod.delete_task(player.force, tags.task_id) then
      gui.refresh_force_boards(player.force)
    end

  elseif action == "kanbantorio_clear_done" then
    if pstate.is_pinned then return end
    local removed = storage_mod.clear_done_tasks(player.force, pstate.selected_surface or storage_mod.ALL_SURFACES_KEY)
    if removed > 0 then
      gui.refresh_force_boards(player.force)
    end

  elseif action == "kanbantorio_card_bp_attach" then
    if pstate.is_pinned then return end
    local task = storage_mod.find_task(player.force, tags.task_id)
    if not task then return end

    if blueprints.is_holding_blueprint(player) then
      local bp_entry, err = blueprints.extract_from_cursor(player)
      if not bp_entry then
        if err then player.print(err) end
        return
      end
      task.blueprints = task.blueprints or {}
      table.insert(task.blueprints, bp_entry)
      player.print({"kanbantorio.msg-bp-attached", bp_entry.label, task.id})
      gui.refresh_force_boards(player.force)
    else
      local stack = player.cursor_stack
      local has_other_item = stack and stack.valid_for_read
      if has_other_item then
        player.print({"kanbantorio.msg-bp-invalid-cursor"})
      else
        gui.open_bp_modal(player, {
          mode = "import",
          target = "task",
          task_id = task.id
        })
      end
    end

  elseif action == "kanbantorio_card_bp_click" then
    local task = storage_mod.find_task(player.force, tags.task_id)
    if not (task and task.blueprints) then return end
    local bp_idx = tags.bp_index
    local bp = task.blueprints[bp_idx]
    if not bp then return end

    if event.button == defines.mouse_button_type.right then
      if pstate.is_pinned then
        gui.open_bp_modal(player, {
          mode = "export",
          target = "view",
          task_id = task.id,
          bp_index = bp_idx
        })
      elseif event.shift then
        local removed_label = bp.label or "Blueprint"
        table.remove(task.blueprints, bp_idx)
        player.print({"kanbantorio.msg-bp-removed", removed_label, task.id})
        gui.refresh_force_boards(player.force)
      else
        gui.open_bp_modal(player, {
          mode = "export",
          target = "task",
          task_id = task.id,
          bp_index = bp_idx
        })
      end
    elseif event.button == defines.mouse_button_type.left then
      blueprints.give_to_cursor(player, bp)
    end

  elseif action == "kanbantorio_view_bp_click" then
    local task = storage_mod.find_task(player.force, tags.task_id)
    if not (task and task.blueprints) then return end
    local bp = task.blueprints[tags.bp_index]
    if not bp then return end

    if event.button == defines.mouse_button_type.right then
      gui.open_bp_modal(player, {
        mode = "export",
        target = "view",
        task_id = task.id,
        bp_index = tags.bp_index
      })
    elseif event.button == defines.mouse_button_type.left then
      blueprints.give_to_cursor(player, bp)
    end

  elseif action == "kanbantorio_modal_bp_drop" then
    local bp_entry, err = blueprints.extract_from_cursor(player)
    if not bp_entry then
      if err then player.print(err) end
      return
    end
    pstate.modal_draft_bps = pstate.modal_draft_bps or {}
    table.insert(pstate.modal_draft_bps, bp_entry)
    gui.refresh_modal_blueprints(player)

  elseif action == "kanbantorio_modal_bp_click" then
    local bps = pstate.modal_draft_bps
    if not bps then return end
    local bp_idx = tags.bp_index
    local bp = bps[bp_idx]
    if not bp then return end

    if event.button == defines.mouse_button_type.right then
      if event.shift then
        table.remove(bps, bp_idx)
        gui.refresh_modal_blueprints(player)
      else
        gui.open_bp_modal(player, {
          mode = "export",
          target = "modal",
          bp_index = bp_idx
        })
      end
    elseif event.button == defines.mouse_button_type.left then
      blueprints.give_to_cursor(player, bp)
    end

  elseif action == "kanbantorio_open_bp_import_modal" then
    gui.open_bp_modal(player, {
      mode = "import",
      target = tags.target,
      task_id = tags.task_id
    })

  elseif action == "kanbantorio_close_bp_modal" then
    if player.gui.screen.kanbantorio_bp_modal then
      player.gui.screen.kanbantorio_bp_modal.destroy()
    end

  elseif action == "kanbantorio_confirm_bp_import" then
    local bp_modal = player.gui.screen.kanbantorio_bp_modal
    if not bp_modal then return end
    local body = bp_modal.kanbantorio_bp_modal_body
    if not body then return end

    local custom_label = body.kanbantorio_bp_label_input and body.kanbantorio_bp_label_input.text or ""
    local raw_str = body.kanbantorio_bp_string_input and body.kanbantorio_bp_string_input.text or ""

    local bp_entry, msg = blueprints.parse_blueprint_string(player.force, raw_str, custom_label)
    if not bp_entry then
      if msg then player.print(msg) end
      return
    end
    if msg then
      player.print(msg)
    end

    if tags.target == "modal" then
      pstate.modal_draft_bps = pstate.modal_draft_bps or {}
      table.insert(pstate.modal_draft_bps, bp_entry)
      bp_modal.destroy()
      gui.refresh_modal_blueprints(player)
    else
      local task = storage_mod.find_task(player.force, tags.task_id)
      if task then
        task.blueprints = task.blueprints or {}
        table.insert(task.blueprints, bp_entry)
        player.print({"kanbantorio.msg-bp-attached", bp_entry.label, task.id})
      end
      bp_modal.destroy()
      gui.refresh_force_boards(player.force)
    end

  elseif action == "kanbantorio_bp_update_label" then
    local bp_modal = player.gui.screen.kanbantorio_bp_modal
    if not bp_modal then return end
    local body = bp_modal.kanbantorio_bp_modal_body
    local new_label = body and body.kanbantorio_bp_label_input and body.kanbantorio_bp_label_input.text or ""
    new_label = new_label:match("^%s*(.-)%s*$")

    if tags.target == "modal" then
      local bp = pstate.modal_draft_bps and pstate.modal_draft_bps[tags.bp_index]
      if bp and new_label ~= "" then
        bp.label = new_label
      end
      bp_modal.destroy()
      gui.refresh_modal_blueprints(player)
    else
      local task = storage_mod.find_task(player.force, tags.task_id)
      local bp = task and task.blueprints and task.blueprints[tags.bp_index]
      if bp and new_label ~= "" then
        bp.label = new_label
      end
      bp_modal.destroy()
      gui.refresh_force_boards(player.force)
    end
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local tags = element.tags
  local action = tags and tags.action
  if not action then return end

  if action == "kanbantorio_surface_changed" then
    local pstate = storage_mod.get_player_state(player)
    local skeys = tags.surface_keys or {}
    pstate.selected_surface = skeys[element.selected_index] or storage_mod.ALL_SURFACES_KEY
    gui.refresh_board_columns(player)

  elseif action == "kanbantorio_assignee_filter_changed" then
    local pstate = storage_mod.get_player_state(player)
    local fvals = tags.filter_values or {}
    pstate.assignee_filter = fvals[element.selected_index] or "__all__"
    gui.refresh_board_columns(player)

  elseif action == "kanbantorio_card_assignee_changed" then
    local task = storage_mod.find_task(player.force, tags.task_id)
    if task then
      local avals = tags.assignee_values or {}
      local chosen = avals[element.selected_index]
      task.assignee = (chosen and chosen ~= "") and chosen or nil
      gui.refresh_force_boards(player.force)
    end
  end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local tags = element.tags
  local action = tags and tags.action
  if action == "kanbantorio_search_changed" then
    local pstate = storage_mod.get_player_state(player)
    pstate.search_query = element.text or ""
    gui.refresh_board_columns(player)
  end
end)

script.on_event(defines.events.on_gui_confirmed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local tags = element.tags
  local action = tags and tags.action
  if action == "kanbantorio_quick_add_confirm" then
    handle_quick_add(player)
  end
end)
