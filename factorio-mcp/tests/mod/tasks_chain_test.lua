-- Offline unit tests for scripts/tasks.lua quiet/chain semantics (run_plan's
-- foundations). Stubs every runner module. Run: lua tests/mod/tasks_chain_test.lua
local here = (arg and arg[0] or "."):match("^(.*)/[^/]+$") or "."
package.path = here .. "/../../mod/factorio-mcp/?.lua;" .. package.path

local failures = 0
local function check(cond, what)
  if cond then print("ok   " .. what) else failures = failures + 1 print("FAIL " .. what) end
end

-- ------------------------------------------------------------ module stubs
package.loaded["scripts.companion"] = {
  DEFAULT = "AI",
  set_context = function() end,
  context = function() return "AI" end,
  require_companion = function() return {} end,
  get = function() return nil end,
}
local pushed = {}
package.loaded["scripts.events"] = {
  push = function(kind, text) pushed[#pushed + 1] = kind end,
}
-- Every runner: start errors when task.boom, tick finishes with task.outcome.
local runner = {
  start = function(t) if t.boom then error("boom") end end,
  tick = function(t) return { status = t.outcome or "done", detail = "x" } end,
}
runner.place, runner.rotate, runner.set_recipe = runner, runner, runner
package.loaded["scripts.belts"] = { measure = runner, trace = function() end }
runner.insert, runner.extract, runner.deliver = runner, runner, runner
for _, m in ipairs({ "walk", "follow", "mine", "build", "craft", "transfer", "refuel",
  "drive", "build_plan", "deconstruct", "fight", "defend", "build_blueprint", "wait_until", "say" }) do
  package.loaded["scripts.actions." .. m] = runner
end

_G.storage = { tasks = { next_id = 1, records = {}, by_companion = {}, failed_chains = {} } }
_G.game = { tick = 100 }
_G.defines = { shooting = { not_shooting = 0 } }

local tasks = require("scripts.tasks")
local function status_of(id)
  local rec = storage.tasks.records[id]
  return rec and rec.status or "pending"
end

do -- quiet chain: only the last (loud) success emits an event
  local a = tasks.enqueue({ task = { type = "walk_to" }, background = true, quiet = true, chain = "ok1" })
  local b = tasks.enqueue({ task = { type = "walk_to" } , background = true, chain = "ok1" })
  tasks.on_tick() -- a
  tasks.on_tick() -- b
  check(status_of(a.task_id) == "done" and status_of(b.task_id) == "done", "chain: both steps ran")
  check(#pushed == 1 and pushed[1] == "job_done", "chain: exactly ONE job_done (quiet steps silent)")
end

do -- failure cancels queued chain-mates, one task_failed event
  pushed = {}
  package.loaded["scripts.events"].push = function(kind) pushed[#pushed + 1] = kind end
  local a = tasks.enqueue({ task = { type = "walk_to", boom = true }, background = true, quiet = true, chain = "f1" })
  local b = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "f1" })
  tasks.on_tick() -- a starts, fails at start -> b cancelled in the queue
  check(status_of(a.task_id) == "failed", "fail-fast: first step failed")
  check(status_of(b.task_id) == "cancelled", "fail-fast: queued chain-mate cancelled")
  check(#pushed == 1 and pushed[1] == "job_failed", "fail-fast: exactly ONE failure event")
end

do -- race: the failure beats the remaining enqueues -> cancel at enqueue time
  local late = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "f1" })
  check(late.cancelled == true and status_of(late.task_id) == "cancelled",
    "fail-fast race: late enqueue of a failed chain cancels instantly")
end

do -- unrelated chains are untouched
  local c = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "other" })
  tasks.on_tick()
  check(status_of(c.task_id) == "done", "independent chain unaffected")
end

do -- an optional step's failure is reported but the chain goes on
  pushed = {}
  package.loaded["scripts.events"].push = function(kind) pushed[#pushed + 1] = kind end
  local a = tasks.enqueue({ task = { type = "walk_to", boom = true }, background = true, chain = "opt", optional = true })
  local b = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "opt" })
  tasks.on_tick() -- a fails
  tasks.on_tick() -- b
  check(status_of(a.task_id) == "failed" and status_of(b.task_id) == "done", "optional: failure doesn't cancel the rest")
  check(pushed[1] == "optional_job_failed", "optional: reported as optional_job_failed (not job_failed)")
  local late = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "opt" })
  check(not late.cancelled, "optional: the chain is not marked failed")
  tasks.on_tick() -- run `late` so the next block starts with an empty lane
end

do -- an optional step is still cancelled when an earlier required step fails
  local a = tasks.enqueue({ task = { type = "walk_to", boom = true }, background = true, chain = "req" })
  local b = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "req", optional = true })
  tasks.on_tick()
  check(status_of(a.task_id) == "failed" and status_of(b.task_id) == "cancelled", "optional: cancelled by an earlier failure")
end

do -- a repeated request_id (lost reply, client retried) returns the first job instead of a second one
  local a = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "rid", request_id = "req-1" })
  local b = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "rid", request_id = "req-1" })
  check(b.duplicate == true and b.task_id == a.task_id, "request_id: a retried enqueue returns the same job")
  local c = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "rid", request_id = "req-2" })
  check(c.task_id ~= a.task_id and not c.duplicate, "request_id: a new request makes a new job")
  tasks.on_tick() tasks.on_tick()
end

do -- a runner may refuse a task at enqueue time (build_blueprint's provenance gate): no job, nothing cancelled
  runner.validate = function(t) if t.refuse then error("not allowed: " .. t.refuse, 0) end end
  local running = tasks.enqueue({ task = { type = "walk_to" }, background = true, chain = "val" })
  local before = storage.tasks.next_id
  local ok, err = pcall(tasks.enqueue, { task = { type = "walk_to", refuse = "string" }, replace = true, chain = "val" })
  check(not ok and tostring(err):find("not allowed: string", 1, true), "validate: the refusal reaches the caller")
  check(storage.tasks.next_id == before, "validate: a refused task gets no job id")
  check(#storage.tasks.by_companion["AI"].queue == 1, "validate: a refused replace=true leaves the lane alone")
  runner.validate = nil
  tasks.on_tick()
  check(status_of(running.task_id) == "done", "validate: the earlier job still ran")
end

print(failures == 0 and "\nALL TESTS PASSED" or ("\n" .. failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
