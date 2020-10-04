# mwtest
Building a MediaWiki bot in Lua

## My environment
- Windows 7 x64
- luapower
- LuaJIT

As there's no os specific calls or libraries used, I think it could also run well on Linux or Mac. Higher versions of Lua is not tested.

## dykupdate (inactive)
- Set your clock with an internet server (UTC+8)
- Set up your Lua environment and install the dependencies.
- The DYK update code has to run by an admin account (as T:Dyk is cascade protected)

## linky
This is a Lua version of linky for QQ using [CoolQ Socket API](https://github.com/mrhso/cqsocketapi). Mirai Native (CoolQ equavalent) and your client communicates using UDP sockets. Timerwheel is used for sending ClientHello every 5 minutes. An [FFI binding](https://github.com/semyon422/aqua/blob/master/aqua/iconv/init.lua) to libiconv is used for encoding and decoding between GB18030 and UTF-8.
- linky.lua (base QQ bot)
- feed_service.lua (interacts with linky, send feed contents)
- science_data.lua (science articles, no interactions, just write to file)

### Patch to copas.lua
As copas only has `addthread` but no `removethread`, if some of our requests are irresponsive for a long time, copas will never finish. Then we won't have a clean copas for a second run. The `removeall` function could be added to simply removing any threads. Please refer to my copas [fork](https://github.com/AlexanderMisel/copas).
