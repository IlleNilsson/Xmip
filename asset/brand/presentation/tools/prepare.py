"""Prepare presentation transfer data, or collect regenerated narration."""
import argparse
import json
from pathlib import Path
import shutil
import tomllib

MATERIAL = Path(__file__).resolve().parents[1]
ROOT = MATERIAL.parents[2]
WORK = ROOT / '.ai-interaction' / 'presentation'


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def load():
    story = tomllib.loads((MATERIAL / 'story.xmip').read_text(encoding='utf-8'))
    timing = tomllib.loads((MATERIAL / 'audio/timing.xmip').read_text(encoding='utf-8'))
    sections = story['section']
    if len(sections) != len(timing['scene']):
        raise ValueError('Story and audio timing must have the same number of sections.')
    for section in sections:
        for source in section['sources']:
            if not (ROOT / source).is_file():
                raise ValueError(f'Missing project source: {source}')
    return sections, timing['scene']


def matches(section, scene):
    text = ' '.join(item['text'].strip() for item in scene['caption'])
    return text == section['narration']


def prepare(sections, scenes):
    build = WORK / 'build'
    hosts = WORK / 'output' / 'brand-presenters'
    build.mkdir(parents=True, exist_ok=True)
    hosts.mkdir(parents=True, exist_ok=True)
    (build / 'story.json').write_text(json.dumps(sections), encoding='utf-8')
    for source in (MATERIAL / 'assets').glob('*.png'):
        shutil.copyfile(source, hosts / source.name)
    for index, (section, scene) in enumerate(zip(sections, scenes)):
        prefix = build / f'overview-narration-{index}'
        if not matches(section, scene):
            for extension in ('.wav', '.json'):
                prefix.with_suffix(extension).unlink(missing_ok=True)
            print(f'Regenerate narration for section {index + 1}.')
            continue
        shutil.copyfile(MATERIAL / 'audio' / scene['file'], prefix.with_suffix('.wav'))
        prefix.with_suffix('.json').write_text(
            json.dumps(scene['caption']), encoding='utf-8'
        )
    print(f'Prepared {len(sections)} sections in {WORK}.')


def collect(sections):
    lines = ['# Generated sentence timing for the checked-in narration.', '']
    pending = []
    for index, section in enumerate(sections):
        prefix = WORK / 'build' / f'overview-narration-{index}'
        captions = json.loads(prefix.with_suffix('.json').read_text(encoding='utf-8'))
        if not matches(section, {'caption': captions}):
            raise ValueError(f'Regenerated narration differs from section {index + 1}.')
        name = f'scene-{index + 1:02}.wav'
        source = prefix.with_suffix('.wav')
        if not source.is_file():
            raise ValueError(f'Missing audio: {source}')
        pending.append((source, MATERIAL / 'audio' / name))
        lines.extend(['[[scene]]', f'file = {quoted(name)}', ''])
        for caption in captions:
            lines.append('[[scene.caption]]')
            lines.extend(f'{key} = {quoted(value)}' for key, value in caption.items())
            lines.append('')
    for source, destination in pending:
        shutil.copyfile(source, destination)
    (MATERIAL / 'audio/timing.xmip').write_text('\n'.join(lines), encoding='utf-8')
    print('Collected matching narration and timing into the repository.')


def validate(sections, scenes):
    for index, (section, scene) in enumerate(zip(sections, scenes)):
        if not matches(section, scene):
            raise ValueError(f'Audio text differs from section {index + 1}.')
        if not (MATERIAL / 'audio' / scene['file']).is_file():
            raise ValueError(f'Missing voice track for section {index + 1}.')
    print(f'OK: {len(sections)} sections, source references and narration records.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--validate', action='store_true')
    modes.add_argument('--collect-narration', action='store_true')
    args = parser.parse_args()
    sections, scenes = load()
    if args.validate:
        validate(sections, scenes)
    elif args.collect_narration:
        collect(sections)
    else:
        prepare(sections, scenes)
