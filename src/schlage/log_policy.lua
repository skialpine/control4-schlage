-- Schlage never opts into the template's raw Ultra HTTP logging. Each driver
-- has its own Lua module table; keep this policy here rather than forking lib.
local redact = require("lib.redact")
redact.forLog = redact.value
return redact
