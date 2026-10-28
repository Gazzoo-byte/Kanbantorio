local storage_mod = require("scripts.storage")

local M = {}

local SUPPORTED_CURSOR_ITEMS = {
  ["blueprint"] = true,
  ["blueprint-book"] = true,
  ["deconstruction-planner"] = true,
  ["upgrade-planner"] = true
}

local DEFAULT_LABELS = {
  ["blueprint"] = "Blueprint",
  ["blueprint-book"] = "Blueprint Book",
  ["deconstruction-planner"] = "Deconstruction Planner",
  ["upgrade-planner"] = "Upgrade Planner"
}

--- Checks if the player is currently holding a blueprint, book, or planner in cursor_stack or cursor_record.
function M.is_holding_blueprint(player)
  local stack = player.cursor_stack
  if stack and stack.valid_for_read then
    if stack.is_blueprint or stack.is_blueprint_book or stack.is_deconstruction_item or stack.is_upgrade_item then
      return true
    end
  end

  local record = player.cursor_record
  if record and record.valid then
    if SUPPORTED_CURSOR_ITEMS[record.type] then
      return true
    end
  end

  return false
end

--- Extracts a blueprint entry `{ id, label, item_name, data }` from the player's cursor.
--- Returns entry, nil on success or nil, LocalisedString error on failure.
function M.extract_from_cursor(player)
  local stack = player.cursor_stack
  if stack and stack.valid_for_read then
    if stack.is_blueprint or stack.is_blueprint_book or stack.is_deconstruction_item or stack.is_upgrade_item then
      if stack.is_blueprint and not stack.is_blueprint_setup() then
        return nil, {"kanbantorio.msg-bp-empty"}
      end
      local exported = stack.export_stack()
      if not exported or exported == "" then
        return nil, {"kanbantorio.msg-bp-empty"}
      end
      local item_name = stack.name
      local label = stack.label
      if not label or label == "" then
        label = DEFAULT_LABELS[item_name] or "Blueprint"
      end
      return {
        id = storage_mod.next_blueprint_id(player.force),
        label = label,
        item_name = item_name,
        data = exported
      }, nil
    end
  end

  local record = player.cursor_record
  if record and record.valid then
    local rtype = record.type
    if SUPPORTED_CURSOR_ITEMS[rtype] then
      if rtype == "blueprint" and not record.is_blueprint_setup() then
        return nil, {"kanbantorio.msg-bp-empty"}
      end
      local exported = record.export_record()
      if not exported or exported == "" then
        return nil, {"kanbantorio.msg-bp-empty"}
      end
      local label = record.label
      if not label or label == "" then
        label = DEFAULT_LABELS[rtype] or "Blueprint"
      end
      return {
        id = storage_mod.next_blueprint_id(player.force),
        label = label,
        item_name = rtype,
        data = exported
      }, nil
    end
  end

  return nil, {"kanbantorio.msg-bp-invalid-cursor"}
end

--- Validates and imports a blueprint string into a blueprint attachment object.
--- Returns entry, warning_msg_or_nil on success, or nil, error_msg on failure.
function M.parse_blueprint_string(force, raw_string, custom_label)
  if not raw_string then
    return nil, {"kanbantorio.msg-bp-invalid-string"}
  end
  local trimmed = raw_string:match("^%s*(.-)%s*$")
  if trimmed == "" then
    return nil, {"kanbantorio.msg-bp-invalid-string"}
  end

  local inv = game.create_inventory(1)
  local stack = inv[1]
  local ok, status = pcall(function()
    return stack.import_stack(trimmed)
  end)

  if not ok or status == 1 or not stack.valid_for_read then
    inv.destroy()
    return nil, {"kanbantorio.msg-bp-invalid-string"}
  end

  if not (stack.is_blueprint or stack.is_blueprint_book or stack.is_deconstruction_item or stack.is_upgrade_item) then
    inv.destroy()
    return nil, {"kanbantorio.msg-bp-invalid-string"}
  end

  local item_name = stack.name
  local label = custom_label and custom_label:match("^%s*(.-)%s*$") or ""
  if label == "" then
    label = stack.label or DEFAULT_LABELS[item_name] or "Blueprint"
  end

  local normalized = stack.export_stack()
  inv.destroy()

  local warning = nil
  if status == -1 then
    warning = {"kanbantorio.msg-bp-imported-with-warnings"}
  end

  return {
    id = storage_mod.next_blueprint_id(force),
    label = label,
    item_name = item_name,
    data = normalized
  }, warning
end

--- Gives a temporary copy of the attached blueprint into the player's cursor.
function M.give_to_cursor(player, bp_entry)
  if not bp_entry or not bp_entry.data then return false end
  if not player.clear_cursor() then
    return false
  end
  local stack = player.cursor_stack
  if not stack then return false end

  local ok, status = pcall(function()
    return stack.import_stack(bp_entry.data)
  end)
  if not ok or status == 1 or not stack.valid_for_read then
    return false
  end

  player.cursor_stack_temporary = true
  player.print({"kanbantorio.msg-bp-taken", bp_entry.label or "Blueprint"})
  return true
end

return M
