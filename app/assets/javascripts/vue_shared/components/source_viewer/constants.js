// Language map from Rouge::Lexer to highlight.js
// Rouge::Lexer - We use it on the BE to determine the language of a source file (https://github.com/rouge-ruby/rouge/blob/master/docs/Languages.md).
// Highlight.js - We use it on the FE to highlight the syntax of a source file (https://github.com/highlightjs/highlight.js/tree/main/src/languages).
export const ROUGE_TO_HLJS_LANGUAGE_MAP = {
  bsl: '1c',
  actionscript: 'actionscript',
  ada: 'ada',
  apache: 'apache',
  applescript: 'applescript',
  armasm: 'armasm',
  awk: 'awk',
  c: 'c',
  ceylon: 'ceylon',
  clean: 'clean',
  clojure: 'clojure',
  cmake: 'cmake',
  coffeescript: 'coffeescript',
  coq: 'coq',
  cpp: 'cpp',
  crystal: 'crystal',
  csharp: 'csharp',
  css: 'css',
  d: 'd',
  dart: 'dart',
  pascal: 'delphi',
  diff: 'diff',
  jinja: 'django',
  docker: 'dockerfile',
  batchfile: 'dos',
  elixir: 'elixir',
  elm: 'elm',
  erb: 'erb',
  erlang: 'erlang',
  fortran: 'fortran',
  fsharp: 'fsharp',
  gherkin: 'gherkin',
  glsl: 'glsl',
  go: 'go',
  gradle: 'gradle',
  groovy: 'groovy',
  haml: 'haml',
  handlebars: 'handlebars',
  haskell: 'haskell',
  haxe: 'haxe',
  http: 'http',
  hylang: 'hy',
  ini: 'ini',
  isbl: 'isbl',
  java: 'java',
  javascript: 'javascript',
  json: 'json',
  julia: 'julia',
  kotlin: 'kotlin',
  lasso: 'lasso',
  tex: 'latex',
  common_lisp: 'lisp',
  livescript: 'livescript',
  llvm: 'llvm',
  hlsl: 'lsl',
  lua: 'lua',
  make: 'makefile',
  markdown: 'markdown',
  mathematica: 'mathematica',
  matlab: 'matlab',
  moonscript: 'moonscript',
  nginx: 'nginx',
  nim: 'nim',
  nix: 'nix',
  objective_c: 'objectivec',
  ocaml: 'ocaml',
  perl: 'perl',
  php: 'php',
  plaintext: 'plaintext',
  pony: 'pony',
  powershell: 'powershell',
  prolog: 'prolog',
  properties: 'properties',
  protobuf: 'protobuf',
  puppet: 'puppet',
  python: 'python',
  q: 'q',
  qml: 'qml',
  r: 'r',
  reasonml: 'reasonml',
  ruby: 'ruby',
  rust: 'rust',
  sas: 'sas',
  scala: 'scala',
  scheme: 'scheme',
  scss: 'scss',
  shell: 'shell',
  smalltalk: 'smalltalk',
  sml: 'sml',
  sqf: 'sqf',
  sql: 'sql',
  stan: 'stan',
  stata: 'stata',
  swift: 'swift',
  tap: 'tap',
  tcl: 'tcl',
  twig: 'twig',
  typescript: 'typescript',
  vala: 'vala',
  vb: 'vbnet',
  verilog: 'verilog',
  vhdl: 'vhdl',
  viml: 'vim',
  xml: 'xml',
  xquery: 'xquery',
  yaml: 'yaml',
};

export const LINES_PER_CHUNK = 70;
