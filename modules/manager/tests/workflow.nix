{ pkgs }:
pkgs.runCommand "folio-cli-workflow"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.gnutar
      pkgs.jq
    ];
  }
  ''
    export WORKFLOW_COMMAND=${../cli/commands/workflow/command.py}
    export WORKFLOW_ADAPTER=${./fixtures/workflow_adapter.py}
    python3 ${./test_workflow.py}
    REVIEW_COMMAND=${../runtime/snapshot/review.py} python3 ${./test_review.py}
    DEPLOY_COMMAND=${../cli/commands/deploy/command.sh} bash ${./status-fallback.sh}
    mkdir $out
    echo 'Reviewed cross-scope plans, cancellation, comments, stale inputs, build gates, partial failures and rollback passed.' >$out/result
  ''
