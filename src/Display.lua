-- Full-screen status view: a table with one row per maintained entry, a panel with
-- the most recent log lines and a line listing the keys. Used when settings.display
-- is "table"; otherwise the maintainer prints a scrolling log.
local component = require("component")
local term = require("term")
local unicode = require("unicode")

local Display = {}

local HISTORY = 200 -- log lines kept in memory
Display.history = {}

local gpu = nil
local active = false
local suspended = false -- true while another program (edit) uses the screen
local batching = false -- true while a cycle runs; the screen is redrawn once at its end
local rows = {}
local header = ""
local footer = ""
local showRecent = true -- false: no recent log panel, the table uses the whole screen

local COLORS = {
    white = 0xFFFFFF,
    gray = 0xAAAAAA,
    green = 0x55FF55,
    yellow = 0xFFFF55,
    orange = 0xFFAA00,
    red = 0xFF5555,
    cyan = 0x55FFFF,
}

-- Pads or cuts text to exactly `width` characters (cut text ends with "~")
local function fit(text, width)
    text = tostring(text or "")
    local length = unicode.len(text)
    if length > width then
        if width <= 1 then
            return unicode.sub(text, 1, width)
        end
        return unicode.sub(text, 1, width - 1) .. "~"
    end
    return text .. string.rep(" ", width - length)
end

local function fitRight(text, width)
    text = tostring(text or "")
    local length = unicode.len(text)
    if length >= width then
        return fit(text, width)
    end
    return string.rep(" ", width - length) .. text
end

-- Screen areas: line 1 header, line 2 column titles, then the table rows, a
-- separator, the recent log lines, and the key help on the last line. Without the
-- recent panel the table rows go down to the key help line.
local function layout()
    local width, height = gpu.getResolution()
    if not showRecent then
        return width, height, 0, nil, math.max(1, height - 3)
    end
    local logLines = math.max(3, math.floor(height * 0.3))
    local separatorY = height - 1 - logLines
    local tableRows = math.max(1, separatorY - 3)
    return width, height, logLines, separatorY, tableRows
end

local function colorSetter()
    local colors = gpu.getDepth() > 1
    return function(name)
        if colors then
            gpu.setForeground(COLORS[name] or COLORS.white)
        end
    end
end

local STATUS_WIDTH = 17 -- fits "failed, retry 45s"
local MIN_NAME_WIDTH = 16

-- Number columns that fit next to a readable name. On narrow screens Batch is
-- dropped first, then Want, then Stock. Returns the name width and the columns.
local function columnsFor(width)
    local columns = {{title = "Stock", key = "stock", width = 8}, {title = "Want", key = "want", width = 8},
        {title = "Batch", key = "batch", width = 7}}
    while true do
        local used = STATUS_WIDTH + 2
        for _, column in ipairs(columns) do
            used = used + column.width + 1
        end
        if width - used >= MIN_NAME_WIDTH or #columns == 0 then
            -- Capped so the numbers stay next to the names on very wide screens
            return math.max(8, math.min(50, width - used)), columns
        end
        table.remove(columns)
    end
end

local function formatRow(nameWidth, columns, row)
    local line = fit(row.name, nameWidth)
    for _, column in ipairs(columns) do
        line = line .. " " .. fitRight(row[column.key], column.width)
    end
    return line .. "  " .. row.status
end

local function drawTable()
    local width, _, _, separatorY, tableRows = layout()
    local setColor = colorSetter()
    local nameWidth, columns = columnsFor(width)

    setColor("cyan")
    gpu.set(1, 1, fit(header, width))
    setColor("gray")
    local titles = {name = "Name", status = "Status"}
    for _, column in ipairs(columns) do
        titles[column.key] = column.title
    end
    gpu.set(1, 2, fit(formatRow(nameWidth, columns, titles), width))

    local shown = #rows
    if shown > tableRows then
        shown = tableRows - 1 -- leave a line for "... and N more"
    end
    for i = 1, tableRows do
        local y = 2 + i
        local row = rows[i]
        if i <= shown and row then
            setColor(row.color)
            gpu.set(1, y, fit(formatRow(nameWidth, columns, row), width))
        elseif i == shown + 1 and #rows > shown then
            setColor("gray")
            gpu.set(1, y, fit("... and " .. (#rows - shown) .. " more (a bigger screen shows more rows)", width))
        else
            gpu.fill(1, y, width, 1, " ")
        end
    end

    if separatorY then
        setColor("gray")
        gpu.set(1, separatorY, fit("-- Recent " .. string.rep("-", math.max(0, width - 10)), width))
    end
end

local function drawLog()
    local width, height, logLines, separatorY = layout()
    local setColor = colorSetter()
    local first = math.max(1, #Display.history - logLines + 1)
    for i = 0, logLines - 1 do
        local line = Display.history[first + i]
        local y = separatorY + 1 + i
        if line then
            if line:find("ERROR", 1, true) then
                setColor("red")
            elseif line:find("WARNING", 1, true) then
                setColor("orange")
            else
                setColor("white")
            end
            gpu.set(1, y, fit(line, width))
        else
            gpu.fill(1, y, width, 1, " ")
        end
    end
    setColor("gray")
    gpu.set(1, height, fit(footer, width))
    setColor("white")
end

local failed = false -- the table broke once; stay with the scrolling log from then on

-- Runs a drawing function. A problem while drawing must never stop the maintainer,
-- so on an error the table is switched off and the log is printed normally instead.
local function guarded(draw)
    local ok, err = pcall(draw)
    if not ok then
        failed = true
        active = false
        setLogHandler(nil)
        pcall(term.clear)
        pcall(term.setCursorBlink, true)
        print("WARNING: the status table failed (" .. tostring(err) .. "); showing a scrolling log instead.")
    end
end

local function drawAll()
    if not active or suspended then
        return
    end
    guarded(function()
        local width, height = gpu.getResolution()
        gpu.fill(1, 1, width, height, " ")
        drawTable()
        drawLog()
    end)
end

-- Takes over the screen. Returns false if there is no graphics card (or the table
-- failed earlier), and the maintainer prints a scrolling log instead.
function Display.start()
    if failed or not component.isAvailable("gpu") then
        return false
    end
    gpu = component.gpu
    active = true
    suspended = false
    term.setCursorBlink(false)
    setLogHandler(Display.addLog)
    drawAll()
    return active
end

-- Gives the screen back to normal printing
function Display.stop()
    if not active then
        return
    end
    active = false
    setLogHandler(nil)
    term.clear()
    term.setCursorBlink(true)
end

-- Shows or hides the recent log panel below the table
function Display.setShowRecent(show)
    if show ~= showRecent then
        showRecent = show
        drawAll()
    end
end

function Display.isActive()
    return active
end

-- While another program uses the screen (e.g. edit), nothing is drawn
function Display.suspend()
    suspended = true
end

function Display.resume()
    suspended = false
    if active then
        term.setCursorBlink(false) -- edit turns the blinking cursor back on when it exits
    end
    drawAll()
end

function Display.addLog(line)
    table.insert(Display.history, line)
    if #Display.history > HISTORY then
        table.remove(Display.history, 1)
    end
    if active and not suspended and not batching then
        guarded(drawLog)
    end
end

-- During a cycle log lines are only collected; the screen is redrawn once at the end
function Display.beginBatch()
    batching = true
end

function Display.endBatch()
    batching = false
    drawAll()
end

-- rows: list of {name, stock, want, batch, status, color}
function Display.update(newRows, newHeader, newFooter)
    rows = newRows
    header = newHeader
    footer = newFooter
    if not batching then
        drawAll()
    end
end

return Display
