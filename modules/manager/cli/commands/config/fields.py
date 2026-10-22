"""Edit named configuration paths without bypassing the durable commit protocol."""
import json
import sys


def resolve(document, path):
    parts = path.split('/')[1:]
    if not path.startswith('/') or not parts or parts[0] not in {'preferences', 'modules'}:
        raise ValueError('Use /preferences/FIELD or /modules/NAME/SETTING')
    if any(not part or '~' in part for part in parts):
        raise ValueError('Empty or escaped path components are unsupported')
    current = document['folio-environment:environment']
    for part in parts[:-1]:
        if isinstance(current, list):
            matches = [entry for entry in current if entry.get('name') == part]
            if len(matches) != 1:
                raise ValueError('Named entry is missing or ambiguous: ' + part)
            current = matches[0]
        elif isinstance(current, dict):
            if part not in current:
                current[part] = {}
            current = current[part]
        else:
            raise ValueError('Path traverses a scalar')
    if not isinstance(current, dict) or (parts[0] == 'modules' and len(parts) < 3):
        raise ValueError('Select an individual setting')
    if parts[0] == 'modules' and parts[-1] == 'name':
        raise ValueError('Module identities cannot be edited')
    return current, parts[-1]


def main():
    try:
        action, path, *values = sys.argv[1:]
        document = json.load(sys.stdin)
        parent, key = resolve(document, path)
        if action == 'get':
            print(json.dumps(parent[key], ensure_ascii=False))
        else:
            if action == 'set':
                parent[key] = json.loads(values[0])
            elif action == 'unset':
                parent.pop(key, None)
            else:
                raise ValueError('Unknown field operation')
            print(json.dumps(document, ensure_ascii=False))
    except (ValueError, KeyError, IndexError, TypeError) as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
