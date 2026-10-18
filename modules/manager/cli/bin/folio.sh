parse_arguments "$@"
if "$help_requested"; then show_help; exit 0; fi
dispatch_command
