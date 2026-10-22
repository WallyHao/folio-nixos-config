"""List complete themes or switch the system and managed desktop together."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


class Failure(Exception):
    def __init__(self, message, status='failure', data=None):
        super().__init__(message)
        self.status = status
        self.data = data


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise Failure(message, 'invalid')


def call(adapter, *args, scope='system', privileged=False):
    env = dict(os.environ, FOLIO_JSON='true', FOLIO_NO_WAIT='false', FOLIO_SCOPE=scope)
    invocation = [os.environ[adapter], *args]
    if privileged and os.geteuid() != 0:
        # Elevate only the system write; the deployment coordinator stays in the
        # desktop session and already owns system/user activation ordering.
        invocation = ['sudo', 'env', 'FOLIO_SCOPE=system', 'FOLIO_JSON=true',
                      'FOLIO_COMMAND=config', 'FOLIO_NO_WAIT=false', *invocation]
    result = subprocess.run(invocation, env=env, stdout=subprocess.PIPE, text=True)
    try:
        reply = json.loads(result.stdout)
    except ValueError:
        raise Failure(f'{args[0]} returned no valid result') from None
    if result.returncode or reply['status'] != 'success':
        raise Failure(reply.get('error') or 'Operation failed', reply['status'])
    return reply['data']


def save(document, digest, *, scope):
    with tempfile.TemporaryDirectory(prefix='folio-theme-') as directory:
        path = Path(directory) / 'configuration.json'
        path.write_text(json.dumps(document))
        return call('FOLIO_CONFIG_ADAPTER', 'import', str(path), '--expected-digest', digest,
                    scope=scope, privileged=scope == 'system')


def remove_legacy_overrides():
    # Old installations could pin a different theme in the desktop document.
    # Remove only those obsolete fields, preserving fonts and other settings.
    current = call('FOLIO_CONFIG_ADAPTER', 'show', scope='user')
    document = current['configuration']
    before = json.dumps(document, sort_keys=True)
    environment = document['folio-environment:environment']
    preferences = environment.get('preferences', {})
    preferences.pop('scheme', None)
    preferences.pop('appearance', None)
    for module in environment.get('modules', []):
        module.get('folio-appearance:appearance', {}).pop('appearance', None)
    if json.dumps(document, sort_keys=True) != before:
        save(document, current['digest'], scope='user')


def main():
    catalogue = json.loads(Path(os.environ['FOLIO_THEME_CATALOGUE']).read_text())
    themes = {f'{scheme}-{mode}': {'scheme': scheme, 'appearance': mode}
              for scheme, modes in catalogue.items() for mode in modes}
    parser = Parser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('list')
    sub.add_parser('set').add_argument('theme', choices=sorted(themes))
    args = parser.parse_args()
    if args.action == 'list':
        return {'themes': sorted(themes)}
    source = Path(os.environ['FOLIO_THEME_SOURCE'])
    if not (source / 'flake.nix').is_file():
        raise Failure('Installed theme source is unavailable', 'unavailable')
    selected = themes[args.theme]
    current = call('FOLIO_CONFIG_ADAPTER', 'show')
    # Read both documents before any mutation so missing services fail early.
    remove_legacy_overrides()
    document = current['configuration']
    document['folio-environment:environment'].setdefault('preferences', {}).update(selected)
    saved = save(document, current['digest'], scope='system')
    result = {'theme': args.theme, 'saved': saved, 'applied': False}
    try:
        plan = call('FOLIO_WORKFLOW_ADAPTER', 'plan', '--source', str(source),
                    '--yes', '--comment', f'Switch system theme to {args.theme}')
        result['planId'] = plan['planId']
        if plan['planId'] is not None:
            call('FOLIO_WORKFLOW_ADAPTER', 'build', plan['planId'])
            call('FOLIO_WORKFLOW_ADAPTER', 'apply', plan['planId'])
        result['applied'] = True
    except Failure as error:
        raise Failure(f'Theme saved but not fully applied: {error}. Use folio status/history to inspect and retry.',
                      error.status, result) from error
    return result


if __name__ == '__main__':
    os.umask(0o077)
    try:
        data = main()
        reply = {'status': 'success', 'data': data, 'error': None, 'taskId': None}
        code = 0
    except (Failure, ValueError, OSError, KeyError) as error:
        status = error.status if isinstance(error, Failure) else 'failure'
        data = error.data if isinstance(error, Failure) else None
        reply = {'status': status, 'data': data, 'error': str(error), 'taskId': None}
        code = {'invalid': 2, 'unavailable': 3, 'conflict': 4}.get(status, 1)
    if os.environ.get('FOLIO_JSON') == 'true':
        print(json.dumps(reply))
    elif code:
        print(reply['error'], file=sys.stderr)
    elif 'themes' in reply['data']:
        print('\n'.join(reply['data']['themes']))
    else:
        print(f'Theme applied: {reply["data"]["theme"]}')
    sys.exit(code)
