local M = {}

M.COLUMNS = {
  { id = "todo", caption = {"kanbantorio.column-todo"} },
  { id = "in_progress", caption = {"kanbantorio.column-in_progress"} },
  { id = "done", caption = {"kanbantorio.column-done"} }
}

M.COLUMN_INDEX = {
  todo = 1,
  in_progress = 2,
  done = 3
}

M.PRIORITIES = {
  { id = "low", caption = {"kanbantorio.priority-low"}, style = "kanbantorio_priority_low" },
  { id = "normal", caption = {"kanbantorio.priority-normal"}, style = "kanbantorio_priority_normal" },
  { id = "high", caption = {"kanbantorio.priority-high"}, style = "kanbantorio_priority_high" }
}

M.PRIORITY_INDEX = {
  low = 1,
  normal = 2,
  high = 3
}

M.ALL_SURFACES_KEY = "__all__"

function M.ensure_storage()
  storage.forces = storage.forces or {}
  storage.players = storage.players or {}
end

function M.get_force_data(force)
  M.ensure_storage()
  local idx = force.index
  local data = storage.forces[idx]
  if not data then
    data = {
      next_task_id = 1,
      next_bp_id = 1,
      tasks = {}
    }
    storage.forces[idx] = data
  end
  return data
end

function M.get_player_state(player)
  M.ensure_storage()
  local idx = player.index
  local state = storage.players[idx]
  if not state then
    local default_surface = (player.surface and player.surface.valid) and player.surface.name or "nauvis"
    state = {
      selected_surface = default_surface,
      assignee_filter = "__all__",
      search_query = "",
      modal_draft_bps = nil,
      editing_task_id = nil
    }
    storage.players[idx] = state
  end
  return state
end

--- Builds a rich display caption for a surface or planet key.
function M.get_surface_display_caption(surface_name)
  if surface_name == M.ALL_SURFACES_KEY then
    return {"kanbantorio.all-surfaces"}
  end

  local planet = game.planets and game.planets[surface_name]
  if planet and planet.valid then
    return {"", "[planet=" .. planet.name .. "] ", planet.prototype.localised_name}
  end

  local surface = game.surfaces[surface_name]
  if surface and surface.valid then
    if surface.planet and surface.planet.valid then
      local p = surface.planet
      return {"", "[planet=" .. p.name .. "] ", p.prototype.localised_name}
    end
    if surface.platform and surface.platform.valid then
      local icon = prototypes.item["space-platform-foundation"] and "[item=space-platform-foundation] " or "[img=utility/space_platform] "
      return {"", icon, surface.platform.name}
    end
    if surface.localised_name then
      return {"", "[img=utility/map] ", surface.localised_name}
    end
    return "[img=utility/map] " .. surface.name
  end

  return "[img=utility/map] " .. tostring(surface_name)
end

--- Checks whether a surface is currently accessible/discovered by the given force.
function M.is_surface_accessible(force, surface)
  if not (force and force.valid and surface and surface.valid) then
    return false
  end

  -- Respect Factorio's per-force hidden surface flag
  if force.get_surface_hidden(surface) then
    return false
  end

  -- Space platform surfaces: accessible if owned by this force
  if surface.platform and surface.platform.valid then
    return surface.platform.force.index == force.index
  end

  -- Planet surfaces: planet must not be hidden and must be unlocked for this force
  if surface.planet and surface.planet.valid then
    if surface.planet.prototype.hidden then
      return false
    end
    if force.is_space_location_unlocked and not force.is_space_location_unlocked(surface.planet.name) then
      return false
    end
  end

  -- Default starting surface is always accessible unless explicitly hidden
  if surface.name == "nauvis" then
    return true
  end

  -- Fast check: origin chunk {0, 0} charted by this force
  if force.is_chunk_charted(surface, { x = 0, y = 0 }) then
    return true
  end

  -- Check if any player on the force is currently on this surface
  for _, player in pairs(force.players) do
    if player.valid and player.surface and player.surface.index == surface.index then
      return true
    end
  end

  -- Fallback: check if any generated chunk on this surface has been charted by the force
  local checked = 0
  for chunk in surface.get_chunks() do
    if force.is_chunk_charted(surface, { x = chunk.x, y = chunk.y }) then
      return true
    end
    checked = checked + 1
    if checked >= 256 then
      break
    end
  end

  return false
end

--- Returns ordered list of surface entries for the force:
--- Each entry: { key = string, caption = LocalisedString, raw_caption = LocalisedString }
function M.get_surface_entries(force, include_all_option)
  local entries = {}
  local seen = {}

  local force_data = M.get_force_data(force)
  local counts = {}
  local total_count = 0
  for _, task in ipairs(force_data.tasks) do
    local sname = task.surface_name or "nauvis"
    counts[sname] = (counts[sname] or 0) + 1
    total_count = total_count + 1
  end

  local function with_count(caption, count)
    if count and count > 0 then
      return {"", caption, " (" .. count .. ")"}
    end
    return caption
  end

  if include_all_option then
    table.insert(entries, {
      key = M.ALL_SURFACES_KEY,
      caption = with_count({"kanbantorio.all-surfaces"}, total_count),
      raw_caption = {"kanbantorio.all-surfaces"}
    })
  end

  local function add_surface_key(key)
    if not key or seen[key] then return end
    seen[key] = true
    local raw_caption = M.get_surface_display_caption(key)
    table.insert(entries, {
      key = key,
      caption = with_count(raw_caption, counts[key]),
      raw_caption = raw_caption
    })
  end

  -- 1. Accessible surfaces in game.surfaces (planetsfirst, then platforms, then other surfaces)
  local planet_surfaces = {}
  local platform_surfaces = {}
  local other_surfaces = {}

  for name, surface in pairs(game.surfaces) do
    if M.is_surface_accessible(force, surface) then
      if surface.planet and surface.planet.valid then
        table.insert(planet_surfaces, name)
      elseif surface.platform and surface.platform.valid then
        table.insert(platform_surfaces, name)
      else
        table.insert(other_surfaces, name)
      end
    end
  end

  for _, name in ipairs(planet_surfaces) do
    add_surface_key(name)
  end
  for _, name in ipairs(platform_surfaces) do
    add_surface_key(name)
  end
  for _, name in ipairs(other_surfaces) do
    add_surface_key(name)
  end

  -- 2. Any surface names that already have tasks on this force's board
  for _, task in ipairs(force_data.tasks) do
    if task.surface_name then
      add_surface_key(task.surface_name)
    end
  end

  if #entries == 0 or (include_all_option and #entries == 1) then
    add_surface_key("nauvis")
  end

  return entries
end

--- Returns ordered list of player names for a player's force:
--- Ordered as: <current player>, then <everyone else on the force sorted alphabetically>.
function M.get_ordered_assignee_names(player, extra_assignee)
  local force = player.force
  local current_name = player.name
  local others = {}
  local seen = {}

  if current_name and current_name ~= "" then
    seen[current_name] = true
  end

  for _, p in pairs(force.players) do
    if p.valid and p.name and p.name ~= "" and not seen[p.name] then
      table.insert(others, p.name)
      seen[p.name] = true
    end
  end
  table.sort(others)

  local names = {}
  if current_name and current_name ~= "" then
    table.insert(names, current_name)
  end
  for _, name in ipairs(others) do
    table.insert(names, name)
  end

  if extra_assignee and extra_assignee ~= "" and not seen[extra_assignee] then
    table.insert(names, extra_assignee)
  end
  return names
end

function M.find_task(force, task_id)
  local force_data = M.get_force_data(force)
  for index, task in ipairs(force_data.tasks) do
    if task.id == task_id then
      return task, index
    end
  end
  return nil, nil
end

function M.create_task(force, params)
  local force_data = M.get_force_data(force)
  local id = force_data.next_task_id
  force_data.next_task_id = id + 1

  local task = {
    id = id,
    title = params.title or ("Task #" .. id),
    description = params.description or "",
    status = params.status or "todo", -- Always defaults to "To Do"
    surface_name = params.surface_name or "nauvis",
    assignee = params.assignee,
    priority = params.priority or "normal",
    blueprints = params.blueprints or {},
    created_by = params.created_by or "",
    created_tick = game.tick
  }

  table.insert(force_data.tasks, task)
  return task
end

function M.delete_task(force, task_id)
  local force_data = M.get_force_data(force)
  for i, task in ipairs(force_data.tasks) do
    if task.id == task_id then
      table.remove(force_data.tasks, i)
      return true
    end
  end
  return false
end

function M.clear_done_tasks(force, surface_filter)
  local force_data = M.get_force_data(force)
  local kept = {}
  local removed = 0
  for _, task in ipairs(force_data.tasks) do
    local matches_surface = (surface_filter == M.ALL_SURFACES_KEY) or (task.surface_name == surface_filter)
    if task.status == "done" and matches_surface then
      removed = removed + 1
    else
      table.insert(kept, task)
    end
  end
  force_data.tasks = kept
  return removed
end

--- Moves a task to `target_col_id`, optionally placing it at `target_task_id`'s position
--- (or at the end of the column if `target_task_id` is nil).
function M.move_task_to_target(force, task_id, target_col_id, target_task_id)
  local force_data = M.get_force_data(force)
  local task, idx = M.find_task(force, task_id)
  if not task or not idx then return false end

  if target_col_id and M.COLUMN_INDEX[target_col_id] then
    task.status = target_col_id
  end

  if target_task_id then
    if target_task_id ~= task_id then
      local _, orig_target_idx = M.find_task(force, target_task_id)
      table.remove(force_data.tasks, idx)
      local _, new_target_idx = M.find_task(force, target_task_id)
      if new_target_idx then
        if orig_target_idx and idx < orig_target_idx then
          table.insert(force_data.tasks, new_target_idx + 1, task)
        else
          table.insert(force_data.tasks, new_target_idx, task)
        end
      else
        table.insert(force_data.tasks, task)
      end
    end
  else
    table.remove(force_data.tasks, idx)
    table.insert(force_data.tasks, task)
  end

  return true
end

function M.next_blueprint_id(force)
  local force_data = M.get_force_data(force)
  local id = force_data.next_bp_id or 1
  force_data.next_bp_id = id + 1
  return id
end

return M
