"""Check module-owned prerequisites before persisting a configuration draft."""
import json
import sys


def findings(document, catalogue):
    environment = document['folio-environment:environment']
    scope = environment['scope']
    selected = {m['name']: m for m in environment['modules'] if m.get('enabled', False)}
    errors = []
    for name, settings in selected.items():
        for rule in catalogue.get(name, {}).get('requirements', {}).get(scope, {}).get('modules', []):
            dependency = rule if isinstance(rule, str) else rule['module']
            if isinstance(rule, dict):
                value = settings
                condition = rule.get('when', {})
                for part in condition.get('path', []):
                    value = value.get(part, condition.get('default')) if isinstance(value, dict) else condition.get('default')
                if value != condition.get('equals', True):
                    continue
            if dependency not in selected:
                errors.append(f'{name} requires enabled {dependency}; enable it or adjust/disable {name} first')
    return errors


if __name__ == '__main__':
    errors = findings(json.load(open(sys.argv[1])), json.load(open(sys.argv[2])))
    if errors:
        print('; '.join(errors))
        raise SystemExit(2)
