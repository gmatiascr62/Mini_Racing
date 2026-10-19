class_name NetConfig
extends RefCounted
## Online settings. DEFAULT_SERVER_URL is the public server on Render; the CI
## workflow replaces it when the repository variable MINI_RACING_SERVER_URL is
## set. Players can also change it in-game (MENU > SERVIDOR).

const DEFAULT_SERVER_URL := "wss://mini-racing-server.onrender.com"
## Default of older versions; a saved URL equal to it is replaced by the new one.
const OLD_DEFAULT_URL := "ws://127.0.0.1:9080"
const DEFAULT_PORT := 9080
const PROTOCOL := 1
const SNAPSHOT_EVERY := 2
const CONNECT_TIMEOUT := 45.0
