#!/usr/bin/env python3
"""Check actual release DEX definitions required by LibVLC's native upcalls."""
import argparse
from pathlib import Path
import re
import struct
import zipfile


def dex_definitions(data):
    if not data.startswith(b'dex\n'):
        raise ValueError('Expected standard Android DEX data.')

    def word(offset):
        return struct.unpack_from('<I', data, offset)[0]

    def uleb(offset):
        value = 0
        for shift in range(0, 35, 7):
            byte = data[offset]
            offset += 1
            value |= (byte & 127) << shift
            if not byte & 128:
                return value, offset
        raise ValueError('Invalid DEX integer.')

    string_count, strings_offset = word(56), word(60)
    strings = []
    for index in range(string_count):
        _, offset = uleb(word(strings_offset + index * 4))
        end = data.index(b'\0', offset)
        strings.append(data[offset:end].decode('utf-8', errors='replace'))
    types_offset = word(68)
    types = [strings[word(types_offset + index * 4)] for index in range(word(64))]
    fields_offset, methods_offset = word(84), word(92)
    result = {}
    for index in range(word(96)):
        offset = word(100) + index * 32
        name = types[word(offset)]
        members = {'methods': set(), 'fields': set()}
        result[name] = members
        offset = word(offset + 24)
        if not offset:
            continue
        sizes = []
        for _ in range(4):
            size, offset = uleb(offset)
            sizes.append(size)
        for size in sizes[:2]:
            field = 0
            for _ in range(size):
                difference, offset = uleb(offset)
                field += difference
                _, offset = uleb(offset)
                members['fields'].add(strings[word(fields_offset + field * 8 + 4)])
        for size in sizes[2:]:
            method = 0
            for _ in range(size):
                difference, offset = uleb(offset)
                method += difference
                _, offset = uleb(offset)
                code, offset = uleb(offset)
                # Require a real method body, not just a reference or declaration.
                if code:
                    members['methods'].add(strings[word(methods_offset + method * 8 + 4)])
    return result


def verify(apk_path):
    definitions = {}
    required_classes = {'org/videolan/libvlc/AWindow',
                        'org/videolan/libvlc/interfaces/IMedia$AudioTrack',
                        'org/videolan/libvlc/interfaces/IMedia$VideoTrack',
                        'org/videolan/libvlc/interfaces/IMedia$SubtitleTrack'}
    with zipfile.ZipFile(apk_path) as archive:
        for name in archive.namelist():
            if re.fullmatch(r'classes\d*\.dex', name):
                definitions.update(dex_definitions(archive.read(name)))
            if re.fullmatch(r'lib/[^/]+/libvlcjni\.so', name):
                required_classes.update(match.decode('ascii') for match in
                                        re.findall(rb'org/videolan/libvlc/[A-Za-z0-9_$/]+', archive.read(name)))
    missing = [name for name in sorted(required_classes) if 'L' + name + ';' not in definitions]
    callbacks = {
        'org/videolan/libvlc/Media': ['createAudioTrackFromNative', 'createVideoTrackFromNative',
                                    'createSubtitleTrackFromNative', 'createUnknownTrackFromNative',
                                    'createSlaveFromNative', 'createStatsFromNative'],
        'org/videolan/libvlc/MediaPlayer': ['createTitleFromNative', 'createChapterFromNative',
                                          'createTrackDescriptionFromNative'],
        'org/videolan/libvlc/VLCObject': ['dispatchEventFromNative'],
        'org/videolan/libvlc/AWindow': ['getNativeSurface'],
    }
    for name, methods in callbacks.items():
        actual = definitions.get('L' + name + ';', {}).get('methods', set())
        missing.extend(name + '.' + method for method in methods if method not in actual)
    if 'mInstance' not in definitions.get('Lorg/videolan/libvlc/VLCObject;', {}).get('fields', set()):
        missing.append('org/videolan/libvlc/VLCObject.mInstance')
    if missing:
        raise ValueError('LibVLC native entry points were removed or renamed: ' + ', '.join(missing))
    print('LibVLC native classes, factory methods, callbacks and instance field verified in release DEX.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    verify(parser.parse_args().apk)
