show_help() {
  local help_path command=${arguments[0]:-}
  if [[ -n "$command" ]]; then
    help_path=$(jq -er --arg command "$command" '.[$command].help' @commands@) || emit_error invalid "Unknown command: $command" 2
    cat "$help_path"
    return
  fi
  cat <<'HELP'
Usage: folio [--json] [--environment portable] [--system] COMMAND

Commands:
  config show|edit|import FILE|export FILE   Read or durably save desired data
  modules list|enable NAME|disable NAME     Inspect or change desired selection
  plan [--source DIRECTORY]                Freeze configuration and source
  build|apply PLAN_ID [--request-id ID]     Build or activate a recorded plan
  status [TASK_ID]                         Query observed state or a task
  rollback REVISION_ID [--rebuild]          Restore retained desired data and closure
  cleanup [--apply]                        Preview or remove unreferenced deployment records
  vm build|start|stop|status|cleanup ID     Manage a disposable user VM
  apps list|init|install|update|remove|reconcile|adopt|rollback|prepare|resume|status
                                          Manage owned user Flatpak applications
  devices status|volume|mute|brightness|profile
                                          Observe or control session devices
  --system system reboot|poweroff          Accept a guest power request

User configuration operations require the manager subscriber for writes.
Build/apply wait by default; --no-wait returns the durable task ID.
Offline system rollback/cleanup require root. User maintenance runs as its owner.
HELP
}
