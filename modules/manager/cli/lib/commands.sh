dispatch_command() {
[[ "$environment" == portable ]] || emit_error invalid 'Unknown environment' 2
command=${arguments[0]}
if [[ "$command" == theme ]]; then scope=system; fi
if "$no_wait" && [[ "$command" != build && "$command" != apply && "$command" != resume && "$command" != vm && "$command" != apps ]]; then
  emit_error invalid '--no-wait applies to deployment tasks and VM builds' 2
fi
export FOLIO_SCOPE=$scope FOLIO_JSON=$json FOLIO_ENVIRONMENT=$environment FOLIO_COMMAND=$command FOLIO_NO_WAIT=$no_wait
if [[ "$command" == doctor || "$command" == resume ]]; then exec @workflow@ "$command" "${arguments[@]:1}"; fi
if ! "$scope_explicit"; then
  case "$command" in
    plan|history|build|apply|rollback|status)
      exec @workflow@ "$command" "${arguments[@]:1}"
      ;;
  esac
fi
adapter=$(jq -er --arg command "$command" '.[$command].path' @commands@ 2>/dev/null) || {
  case "$command" in
    plan|build|apply|rollback|status) emit_error unavailable 'This command is not implemented yet' 3 ;;
    *) emit_error invalid "Unknown command: $command" 2 ;;
  esac
}
jq -e --arg command "$command" --arg scope "$scope" '.[$command].scopes | index($scope) != null' @commands@ >/dev/null ||
  emit_error invalid "Command does not support $scope scope" 2
exec "$adapter" "${arguments[@]:1}"
}
