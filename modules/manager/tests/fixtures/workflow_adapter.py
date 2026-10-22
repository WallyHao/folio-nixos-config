"""Process boundary fixture for the reviewed workflow tests; never activates Nix."""
import hashlib
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ['WORKFLOW_FIXTURE'])
path = root / 'state.json'
state = json.loads(path.read_text())
scope, action = os.environ['FOLIO_SCOPE'], os.environ['FOLIO_COMMAND']
args = sys.argv[1:]
settings = state[scope]
state['calls'].append([scope, action, args])

def finish(data=None, status='success', error=None):
    path.write_text(json.dumps(state))
    print(json.dumps({'status': status, 'data': data, 'error': error, 'taskId': None}))
    raise SystemExit({'success': 0, 'invalid': 2, 'unavailable': 3, 'conflict': 4}.get(status, 1))

def option(name, default=None):
    return args[args.index(name) + 1] if name in args else default

if settings.get('unavailable'):
    finish(status='unavailable', error='Scope unavailable')
if action == 'history':
    finish({'plans': list(settings['plans'].values()), 'current': settings['current'],
            'selectedProfile': settings['current']['artifact'], 'desiredDigest': f'{scope}-config-{settings["version"]}',
            'effectsMatch': not settings.get('corrupted', False), 'configurationSaved': True, 'recoveryRequired': False,
            'revisions': list(settings['revisions'].values())})
if action == 'status':
    if not args:
        finish({'health': 'healthy' if settings['version'] == settings['current']['version'] else 'degraded',
                'configurationSaved': True})
    task = settings['tasks'][args[0]]
    if task.get('phase') == 'running':
        task['polls'] = task.get('polls', 1) - 1
        if task['polls'] <= 0:
            task['phase'] = 'succeeded'
    finish({'task': task})
if action == 'plan':
    mode = option('--mode')
    identifier = option('--draft-id')
    if mode == 'cancel':
        settings['drafts'].pop(identifier, None)
        finish()
    if mode == 'preview':
        source = option('--source')
        text = (Path(source) / 'modules/sample.txt').read_text()
        target = f'/nix/store/{scope}-{settings["version"]}'
        plan = {'scope': scope, 'source': source, 'configurationDigest': f'{scope}-config-{settings["version"]}',
                'beforeProfile': settings['current']['artifact'], 'priorDeployment': settings['current'],
                'version': settings['version'], 'sourceText': text, 'review': {
                    'changed': target != settings['current']['artifact'], 'firstDeployment': False,
                    'configurationModules': ['terminal'], 'configurationFields': [],
                    'sourceChanges': [{'path': 'modules/sample.txt', 'module': 'terminal', 'shared': False, 'kind': 'modified'}],
                    'targetArtifact': target, 'baselineArtifact': settings['current']['artifact']}}
        if scope == 'system':
            plan['review']['targetDescriptor'] = {'format': 1, 'version': settings['version']}
        identifier = hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()
        settings['drafts'][identifier] = plan
        if settings.get('editSourceAfterPreview'):
            (root / 'source/modules/sample.txt').write_text('edited after review')
        finish({'planId': identifier, 'plan': plan})
    plan = settings['drafts'].get(identifier)
    if plan is None:
        finish(status='invalid', error='Unknown draft')
    if settings.get('staleOnConfirm') or settings['version'] != plan['version']:
        finish(status='conflict', error='Reviewed configuration changed')
    plan['comment'] = option('--comment', '')
    identifier = hashlib.sha256(json.dumps(plan, sort_keys=True).encode()).hexdigest()
    settings['plans'][identifier] = dict(plan, planId=identifier, status='planned')
    settings['drafts'].pop(option('--draft-id'), None)
    finish({'planId': identifier, 'plan': plan})
identifier = args[0]
if action == 'rollback':
    revision = settings['revisions'].get(identifier)
    if revision is None:
        finish(status='unavailable', error='Unknown revision')
    settings['current'] = revision
    settings['version'] = revision['version']
    finish({'target': identifier})
plan = settings['plans'].get(identifier)
if not plan:
    finish(status='invalid', error='Unknown plan')
if settings.get('fail') == action:
    finish({'reason': 'injected failure'}, status='failure', error=f'Injected {action} failure')
if os.environ.get('FOLIO_NO_WAIT') == 'true':
    task_id = 't-' + hashlib.sha256(f'{action}:{identifier}:{option("--request-id", "default")}'.encode()).hexdigest()[:32]
    tasks = settings.setdefault('tasks', {})
    if task_id in tasks or settings.get('failTask') == action:
        tasks.setdefault(task_id, {'phase': 'failed', 'resultStatus': 'failure',
                                  'error': 'Injected worker failure', 'recoveryRequired': False})
        path.write_text(json.dumps(state))
        print(json.dumps({'status': 'success', 'data': None, 'error': None, 'taskId': task_id}))
        raise SystemExit(0)
if action == 'apply' and scope == 'system':
    time.sleep(float(os.environ.get('WORKFLOW_DELAY', '0')))
if action == 'build':
    plan['status'] = 'built'
elif action == 'apply':
    if plan['status'] not in ('built', 'applied'):
        finish(status='unavailable', error='Not built')
    plan['status'] = 'applied'
    revision = {'planId': identifier, 'revisionId': identifier, 'artifact': plan['review']['targetArtifact'],
                'version': plan['version'], 'configurationDigest': plan['configurationDigest']}
    settings['current'] = revision
    settings['revisions'][identifier] = revision
if os.environ.get('FOLIO_NO_WAIT') == 'true':
    settings.setdefault('tasks', {})[task_id] = {'phase': 'succeeded', 'comment': plan['comment']}
    path.write_text(json.dumps(state))
    print(json.dumps({'status': 'success', 'data': None, 'error': None, 'taskId': task_id}))
    raise SystemExit(0)
finish({'phase': 'succeeded', 'comment': plan['comment']})
