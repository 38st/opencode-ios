"""Import only generated parser/scanner sources and licenses at pinned revisions.
Never builds or executes downloaded source. Re-run with the checked-in manifest.
"""
import io, json, pathlib, tarfile, urllib.request, concurrent.futures
root = pathlib.Path(__file__).resolve().parents[2]
manifest = pathlib.Path(__file__).with_name('manifest.json')
entries = json.loads(manifest.read_text())
def download(entry):
    archive = urllib.request.urlopen(f'https://codeload.github.com/{entry["repo"]}/tar.gz/{entry["revision"]}').read()
    target = root/'Packages/OpencodeKit/Grammars'/entry['name']
    target.mkdir(parents=True,exist_ok=True)
    sub = entry['subpath']
    with tarfile.open(fileobj=io.BytesIO(archive),mode='r:gz') as tar:
        for member in tar.getmembers():
            if not member.isfile(): continue
            path = pathlib.PurePosixPath(*pathlib.PurePosixPath(member.name).parts[1:])
            if '..' in path.parts: continue
            relative = str(path)
            source = (sub+'/' if sub else '')+'src/'
            if relative.startswith(source) and path.suffix in ['.c','.cc','.h']:
                dest = target/pathlib.PurePosixPath(relative[len(source):])
            elif len(path.parts)==1 and path.name.upper().startswith(('LICENSE','COPYING')):
                dest = target/path.name
            elif relative.startswith('common/') and path.suffix == '.h':
                dest = target/'common'/path.name
            else: continue
            dest.parent.mkdir(parents=True,exist_ok=True)
            dest.write_bytes(tar.extractfile(member).read())
    if not (target/'tree_sitter/parser.h').exists():
        (target/'tree_sitter').mkdir(exist_ok=True)
        (target/'tree_sitter/parser.h').write_bytes(urllib.request.urlopen('https://raw.githubusercontent.com/tree-sitter/tree-sitter/v0.25.10/lib/src/parser.h').read())
    scanner = target/'scanner.c'
    if scanner.exists():
        scanner.write_text(scanner.read_text().replace('../../common/scanner.h', 'common/scanner.h'))
    if entry['name'] in ['yaml', 'python']:
        text = scanner.read_text().replace('    return size;', '    return (unsigned)size;')
        text = text.replace('array_reserve(&scanner->delimiters, delimiter_count)', 'array_reserve(&scanner->delimiters, (uint32_t)delimiter_count)').replace('scanner->delimiters.size = delimiter_count;', 'scanner->delimiters.size = (uint32_t)delimiter_count;')
        scanner.write_text(text)
    header = target/'include/Grammar.h'
    header.parent.mkdir(exist_ok=True)
    header.write_text(f'#pragma once\ntypedef struct TSLanguage TSLanguage;\nconst TSLanguage *tree_sitter_{entry["name"]}(void);\n')
    print(entry['name'],entry['revision'],flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
    list(pool.map(download,entries))
