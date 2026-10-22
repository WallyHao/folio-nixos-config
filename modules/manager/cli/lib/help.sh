show_help() {
  local help_path command=${arguments[0]:-}
  case "$command" in
    doctor)
      printf '%s\n' 'Usage: folio doctor' 'Inspect both scopes, prerequisites and interrupted tasks without changing state.'
      return ;;
    resume)
      printf '%s\n' 'Usage: folio [--no-wait] resume WORKFLOW_ID' 'Observe prior tasks, require effect recovery where necessary, then revalidate and retry.'
      return ;;
  esac
  if [[ -n "$command" ]]; then
    help_path=$(jq -er --arg command "$command" '.[$command].help' @commands@) || emit_error invalid "Unknown command: $command" 2
    cat "$help_path"
    return
  fi
  cat <<'HELP'
Usage: folio [--json] [--environment portable] [--user|--system] COMMAND

Commands:
  config show|edit|import FILE|export FILE   Read or durably save desired data
  config get|set|unset /PATH [JSON]         Read or change one setting
  modules list|enable NAME|disable NAME     Inspect or change desired selection
  plan [--source DIRECTORY]                Review system/user changes, confirm, add a comment
  plan --yes --comment TEXT                Create a reviewed plan non-interactively
  build|apply PLAN_ID [--request-id ID]     Build or activate a recorded plan
  status [TASK_ID]                         Query observed state or a task
  doctor                                  Explain deployment problems and next commands
  resume WORKFLOW_ID                       Resume a saved deployment workflow
  history                                 List plans, comments, scopes and executions
  rollback PLAN_ID [--yes]                Preview and restore a successfully applied plan
  cleanup [--apply]                        Preview or remove unreferenced deployment records
  vm build|start|stop|status|cleanup ID     Manage a disposable user VM
  apps list|init|install|update|remove|reconcile|adopt|rollback|prepare|resume|status
                                          Manage owned user Flatpak applications
  network status|connect|disconnect|proxy-mode|proxy-select
                                            System connectivity controls (--system)
  devices status|volume|mute|brightness|profile
                                          Observe or control session devices
  --system system reboot|poweroff          Accept a guest power request

User configuration operations require the manager subscriber for writes.
Unscoped planning reviews both system and user targets from one source snapshot.
--user/--system select the existing scoped deployment interfaces explicitly.
Build/apply wait by default; --no-wait returns the durable workflow ID.
Cross-scope workers verify system activation before applying the user target.
Offline system rollback/cleanup require root. User maintenance runs as its owner.
HELP
}
