" autoload/padrino.vim
" Author:       Tim Pope <vimNOSPAM@tpope.org>

" Install this file as autoload/padrino.vim.

if exists('g:autoloaded_padrino') || &cp
  finish
endif
let g:autoloaded_padrino = '4.3'

let s:cpo_save = &cpo
set cpo&vim

" Utility Functions {{{1

let s:app_prototype = {}
let s:file_prototype = {}
let s:buffer_prototype = {}
let s:readable_prototype = {}

function! s:add_methods(namespace, method_names)
  for name in a:method_names
    let s:{a:namespace}_prototype[name] = s:function('s:'.a:namespace.'_'.name)
  endfor
endfunction

function! s:function(name)
    return function(substitute(a:name,'^s:',matchstr(expand('<sfile>'), '<SNR>\d\+_'),''))
endfunction

function! s:sub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'')
endfunction

function! s:gsub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

function! s:startswith(string,prefix)
  return strpart(a:string, 0, strlen(a:prefix)) ==# a:prefix
endfunction

function! s:compact(ary)
  return s:sub(s:sub(s:gsub(a:ary,'\n\n+','\n'),'\n$',''),'^\n','')
endfunction

function! s:uniq(list)
  let seen = {}
  let i = 0
  while i < len(a:list)
    if has_key(seen,a:list[i])
      call remove(a:list, i)
    else
      let seen[a:list[i]] = 1
      let i += 1
    endif
  endwhile
  return a:list
endfunction

function! s:scrub(collection,item)
  " Removes item from a newline separated collection
  let col = "\n" . a:collection
  let idx = stridx(col,"\n".a:item."\n")
  let cnt = 0
  while idx != -1 && cnt < 100
    let col = strpart(col,0,idx).strpart(col,idx+strlen(a:item)+1)
    let idx = stridx(col,"\n".a:item."\n")
    let cnt += 1
  endwhile
  return strpart(col,1)
endfunction

function! s:escarg(p)
  return s:gsub(a:p,'[ !%#]','\\&')
endfunction

function! s:esccmd(p)
  return s:gsub(a:p,'[!%#]','\\&')
endfunction

function! s:rquote(str)
  " Imperfect but adequate for Ruby arguments
  if a:str =~ '^[A-Za-z0-9_/.:-]\+$'
    return a:str
  elseif &shell =~? 'cmd'
    return '"'.s:gsub(s:gsub(a:str,'\','\\'),'"','\\"').'"'
  else
    return "'".s:gsub(s:gsub(a:str,'\','\\'),"'","'\\\\''")."'"
  endif
endfunction

function! s:sname()
  return fnamemodify(s:file,':t:r')
endfunction

function! s:pop_command()
  if exists("s:command_stack") && len(s:command_stack) > 0
    exe remove(s:command_stack,-1)
  endif
endfunction

function! s:push_chdir(...)
  if !exists("s:command_stack") | let s:command_stack = [] | endif
  if exists("b:padrino_root") && (a:0 ? getcwd() !=# padrino#app().path() : !s:startswith(getcwd(), padrino#app().path()))
    let chdir = exists("*haslocaldir") && haslocaldir() ? "lchdir " : "chdir "
    call add(s:command_stack,chdir.s:escarg(getcwd()))
    exe chdir.s:escarg(padrino#app().path())
  else
    call add(s:command_stack,"")
  endif
endfunction

function! s:app_path(...) dict
  return join([self.root]+a:000,'/')
endfunction

function! s:app_has_file(file) dict
  return filereadable(self.path(a:file))
endfunction

function! s:app_find_file(name, ...) dict abort
  let trim = strlen(self.path())+1
  if a:0
    let path = s:pathjoin(map(s:pathsplit(a:1),'self.path(v:val)'))
  else
    let path = s:pathjoin([self.path()])
  endif
  let suffixesadd = s:pathjoin(get(a:000,1,&suffixesadd))
  let default = get(a:000,2,'')
  let oldsuffixesadd = &l:suffixesadd
  try
    let &suffixesadd = suffixesadd
    " Versions before 7.1.256 returned directories from findfile
    if type(default) == type(0) && (v:version < 702 || default == -1)
      let all = findfile(a:name,path,-1)
      if v:version < 702
        call filter(all,'!isdirectory(v:val)')
      endif
      call map(all,'s:gsub(strpart(fnamemodify(v:val,":p"),trim),"\\\\","/")')
      return default < 0 ? all : get(all,default-1,'')
    elseif type(default) == type(0)
      let found = findfile(a:name,path,default)
    else
      let i = 1
      let found = findfile(a:name,path)
      while v:version < 702 && found != "" && isdirectory(found)
        let i += 1
        let found = findfile(a:name,path,i)
      endwhile
    endif
    return found == "" ? default : s:gsub(strpart(fnamemodify(found,':p'),trim),'\\','/')
  finally
    let &l:suffixesadd = oldsuffixesadd
  endtry
endfunction

call s:add_methods('app',['path','has_file','find_file'])

" Split a path into a list.  From pathogen.vim
function! s:pathsplit(path) abort
  if type(a:path) == type([]) | return copy(a:path) | endif
  let split = split(a:path,'\\\@<!\%(\\\\\)*\zs,')
  return map(split,'substitute(v:val,''\\\([\\, ]\)'',''\1'',"g")')
endfunction

" Convert a list to a path.  From pathogen.vim
function! s:pathjoin(...) abort
  let i = 0
  let path = ""
  while i < a:0
    if type(a:000[i]) == type([])
      let list = a:000[i]
      let j = 0
      while j < len(list)
        let escaped = substitute(list[j],'[\\, ]','\\&','g')
        if exists("+shellslash") && !&shellslash
          let escaped = substitute(escaped,'^\(\w:\\\)\\','\1','')
        endif
        let path .= ',' . escaped
        let j += 1
      endwhile
    else
      let path .= "," . a:000[i]
    endif
    let i += 1
  endwhile
  return substitute(path,'^,','','')
endfunction

function! s:readable_end_of(lnum) dict abort
  if a:lnum == 0
    return 0
  endif
  if self.name() =~# '\.yml$'
    return -1
  endif
  let cline = self.getline(a:lnum)
  let spc = matchstr(cline,'^\s*')
  let endpat = '\<end\>'
  if matchstr(self.getline(a:lnum+1),'^'.spc) && !matchstr(self.getline(a:lnum+1),'^'.spc.endpat) && matchstr(cline,endpat)
    return a:lnum
  endif
  let endl = a:lnum
  while endl <= self.line_count()
    let endl += 1
    if self.getline(endl) =~ '^'.spc.endpat
      return endl
    elseif self.getline(endl) =~ '^=begin\>'
      while self.getline(endl) !~ '^=end\>' && endl <= self.line_count()
        let endl += 1
      endwhile
      let endl += 1
    elseif self.getline(endl) !~ '^'.spc && self.getline(endl) !~ '^\s*\%(#.*\)\=$'
      return 0
    endif
  endwhile
  return 0
endfunction

function! s:endof(lnum)
  return padrino#buffer().end_of(a:lnum)
endfunction

function! s:readable_last_opening_line(start,pattern,limit) dict abort
  let line = a:start
  while line > a:limit && self.getline(line) !~ a:pattern
    let line -= 1
  endwhile
  let lend = self.end_of(line)
  if line > a:limit && (lend < 0 || lend >= a:start)
    return line
  else
    return -1
  endif
endfunction

function! s:lastopeningline(pattern,limit,start)
  return padrino#buffer().last_opening_line(a:start,a:pattern,a:limit)
endfunction

function! s:readable_define_pattern() dict abort
  if self.name() =~ '\.yml$'
    return '^\%(\h\k*:\)\@='
  endif
  let define = '^\s*def\s\+\(self\.\)\='
  if self.name() =~# '\.rake$'
    let define .= "\\\|^\\s*\\%(task\\\|file\\)\\s\\+[:'\"]"
  endif
  if self.name() =~# '/schema\.rb$'
    let define .= "\\\|^\\s*create_table\\s\\+[:'\"]"
  endif
  if self.type_name('test')
    let define .= '\|^\s*test\s*[''"]'
  endif
  return define
endfunction

function! s:readable_last_method_line(start) dict abort
  return self.last_opening_line(a:start,self.define_pattern(),0)
endfunction

function! s:lastmethodline(start)
  return padrino#buffer().last_method_line(a:start)
endfunction

function! s:readable_last_method(start) dict abort
  let lnum = self.last_method_line(a:start)
  let line = self.getline(lnum)
  if line =~# '^\s*test\s*\([''"]\).*\1'
    let string = matchstr(line,'^\s*\w\+\s*\([''"]\)\zs.*\ze\1')
    return 'test_'.s:gsub(string,' +','_')
  elseif lnum
    return s:sub(matchstr(line,'\%('.self.define_pattern().'\)\zs\h\%(\k\|[:.]\)*[?!=]\='),':$','')
  else
    return ""
  endif
endfunction

function! s:lastmethod(...)
  return padrino#buffer().last_method(a:0 ? a:1 : line("."))
endfunction

function! s:readable_last_format(start) dict abort
  if self.type_name('view')
    let format = fnamemodify(self.path(),':r:e')
    if format == ''
      return get({'rhtml': 'html', 'rxml': 'xml', 'rjs': 'js', 'haml': 'html'},fnamemodify(self.path(),':e'),'')
    else
      return format
    endif
  endif
  let rline = self.last_opening_line(a:start,'\C^\s*\%(mail\>.*\|respond_to\)\s*\%(\<do\|{\)\s*|\zs\h\k*\ze|',self.last_method_line(a:start))
  if rline
    let variable = matchstr(self.getline(rline),'\C^\s*\%(mail\>.*\|respond_to\)\s*\%(\<do\|{\)\s*|\zs\h\k*\ze|')
    let line = a:start
    while line > rline
      let match = matchstr(self.getline(line),'\C^\s*'.variable.'\s*\.\s*\zs\h\k*')
      if match != ''
        return match
      endif
      let line -= 1
    endwhile
  endif
  return ""
endfunction

function! s:lastformat(start)
  return padrino#buffer().last_format(a:start)
endfunction

function! s:format(...)
  let format = padrino#buffer().last_format(a:0 > 1 ? a:2 : line("."))
  return format ==# '' && a:0 ? a:1 : format
endfunction

call s:add_methods('readable',['end_of','last_opening_line','last_method_line','last_method','last_format','define_pattern'])

let s:view_types = 'rhtml,erb,rxml,builder,rjs,mab,liquid,haml,dryml,mn'

function! s:viewspattern()
  return '\%('.s:gsub(s:view_types,',','\\|').'\)'
endfunction

function! s:controller(...)
  return padrino#buffer().controller_name(a:0 ? a:1 : 0)
endfunction

function! s:readable_controller_name(...) dict abort
  let f = self.name()
  if has_key(self,'getvar') && self.getvar('padrino_controller') != ''
    return self.getvar('padrino_controller')
  elseif f =~ '\<app/views/layouts/'
    return s:sub(f,'.*<app/views/layouts/(.{-})\..*','\1')
  elseif f =~ '\<app/views/'
    return s:sub(f,'.*<app/views/(.{-})/\k+\.\k+%(\.\k+)=$','\1')
  elseif f =~ '\<app/helpers/.*_helper\.rb$'
    return s:sub(f,'.*<app/helpers/(.{-})_helper\.rb$','\1')
  elseif f =~ '\<app/controllers/.*\.rb$'
    return s:sub(f,'.*<app/controllers/(.{-})%(_controller)=\.rb$','\1')
  elseif f =~ '\<app/mailers/.*\.rb$'
    return s:sub(f,'.*<app/mailers/(.{-})\.rb$','\1')
  elseif f =~ '\<app/apis/.*_api\.rb$'
    return s:sub(f,'.*<app/apis/(.{-})_api\.rb$','\1')
  elseif f =~ '\<test/functional/.*_test\.rb$'
    return s:sub(f,'.*<test/functional/(.{-})%(_controller)=_test\.rb$','\1')
  elseif f =~ '\<test/unit/helpers/.*_helper_test\.rb$'
    return s:sub(f,'.*<test/unit/helpers/(.{-})_helper_test\.rb$','\1')
  elseif f =~ '\<spec/controllers/.*_spec\.rb$'
    return s:sub(f,'.*<spec/controllers/(.{-})%(_controller)=_spec\.rb$','\1')
  elseif f =~ '\<spec/helpers/.*_helper_spec\.rb$'
    return s:sub(f,'.*<spec/helpers/(.{-})_helper_spec\.rb$','\1')
  elseif f =~ '\<spec/views/.*/\w\+_view_spec\.rb$'
    return s:sub(f,'.*<spec/views/(.{-})/\w+_view_spec\.rb$','\1')
  elseif f =~ '\<components/.*_controller\.rb$'
    return s:sub(f,'.*<components/(.{-})_controller\.rb$','\1')
  elseif f =~ '\<components/.*\.'.s:viewspattern().'$'
    return s:sub(f,'.*<components/(.{-})/\k+\.\k+$','\1')
  elseif f =~ '\<app/models/.*\.rb$' && self.type_name('mailer')
    return s:sub(f,'.*<app/models/(.{-})\.rb$','\1')
  elseif f =~ '\<public/stylesheets/.*\.css$'
    return s:sub(f,'.*<public/stylesheets/(.{-})\.css$','\1')
  elseif a:0 && a:1
    return padrino#pluralize(self.model_name())
  endif
  return ""
endfunction

function! s:model(...)
  return padrino#buffer().model_name(a:0 ? a:1 : 0)
endfunction

function! s:readable_model_name(...) dict abort
  let f = self.name()
  if has_key(self,'getvar') && self.getvar('padrino_model') != ''
    return self.getvar('padrino_model')
  elseif f =~ '\<app/models/.*_observer.rb$'
    return s:sub(f,'.*<app/models/(.*)_observer\.rb$','\1')
  elseif f =~ '\<app/models/.*\.rb$'
    return s:sub(f,'.*<app/models/(.*)\.rb$','\1')
  elseif f =~ '\<test/unit/.*_observer_test\.rb$'
    return s:sub(f,'.*<test/unit/(.*)_observer_test\.rb$','\1')
  elseif f =~ '\<test/unit/.*_test\.rb$'
    return s:sub(f,'.*<test/unit/(.*)_test\.rb$','\1')
  elseif f =~ '\<spec/models/.*_spec\.rb$'
    return s:sub(f,'.*<spec/models/(.*)_spec\.rb$','\1')
  elseif f =~ '\<\%(test\|spec\)/fixtures/.*\.\w*\~\=$'
    return padrino#singularize(s:sub(f,'.*<%(test|spec)/fixtures/(.*)\.\w*\~=$','\1'))
  elseif f =~ '\<\%(test\|spec\)/blueprints/.*\.rb$'
    return s:sub(f,'.*<%(test|spec)/blueprints/(.{-})%(_blueprint)=\.rb$','\1')
  elseif f =~ '\<\%(test\|spec\)/exemplars/.*_exemplar\.rb$'
    return s:sub(f,'.*<%(test|spec)/exemplars/(.*)_exemplar\.rb$','\1')
  elseif f =~ '\<\%(test/\|spec/\)\=factories/.*\.rb$'
    return s:sub(f,'.*<%(test/|spec/)=factories/(.{-})%(_factory)=\.rb$','\1')
  elseif f =~ '\<\%(test/\|spec/\)\=fabricators/.*\.rb$'
    return s:sub(f,'.*<%(test/|spec/)=fabricators/(.{-})%(_fabricator)=\.rb$','\1')
  elseif a:0 && a:1
    return padrino#singularize(self.controller_name())
  endif
  return ""
endfunction

call s:add_methods('readable',['controller_name','model_name'])

function! s:readfile(path,...)
  let nr = bufnr('^'.a:path.'$')
  if nr < 0 && exists('+shellslash') && ! &shellslash
    let nr = bufnr('^'.s:gsub(a:path,'/','\\').'$')
  endif
  if bufloaded(nr)
    return getbufline(nr,1,a:0 ? a:1 : '$')
  elseif !filereadable(a:path)
    return []
  elseif a:0
    return readfile(a:path,'',a:1)
  else
    return readfile(a:path)
  endif
endfunction

function! s:file_lines() dict abort
  let ftime = getftime(self.path)
  if ftime > get(self,last_lines_ftime,0)
    let self.last_lines = readfile(self.path())
    let self.last_lines_ftime = ftime
  endif
  return get(self,'last_lines',[])
endfunction

function! s:file_getline(lnum,...) dict abort
  if a:0
    return self.lines[lnum-1 : a:1-1]
  else
    return self.lines[lnum-1]
  endif
endfunction

function! s:buffer_lines() dict abort
  return self.getline(1,'$')
endfunction

function! s:buffer_getline(...) dict abort
  if a:0 == 1
    return get(call('getbufline',[self.number()]+a:000),0,'')
  else
    return call('getbufline',[self.number()]+a:000)
  endif
endfunction

function! s:readable_line_count() dict abort
  return len(self.lines())
endfunction

function! s:environment()
  if exists('$PADRINO_ENV')
    return $PADRINO_ENV
  else
    return "development"
  endif
endfunction

function! s:Complete_environments(...)
  return s:completion_filter(padrino#app().environments(),a:0 ? a:1 : "")
endfunction

function! s:warn(str)
  echohl WarningMsg
  echomsg a:str
  echohl None
  " Sometimes required to flush output
  echo ""
  let v:warningmsg = a:str
endfunction

function! s:error(str)
  echohl ErrorMsg
  echomsg a:str
  echohl None
  let v:errmsg = a:str
endfunction

function! s:debug(str)
  if exists("g:padrino_debug") && g:padrino_debug
    echohl Debug
    echomsg a:str
    echohl None
  endif
endfunction

function! s:buffer_getvar(varname) dict abort
  return getbufvar(self.number(),a:varname)
endfunction

function! s:buffer_setvar(varname, val) dict abort
  return setbufvar(self.number(),a:varname,a:val)
endfunction

call s:add_methods('buffer',['getvar','setvar'])

" }}}1
" "Public" Interface {{{1

" PadrinoRoot() is the only official public function

function! padrino#underscore(str)
  let str = s:gsub(a:str,'::','/')
  let str = s:gsub(str,'(\u+)(\u\l)','\1_\2')
  let str = s:gsub(str,'(\l|\d)(\u)','\1_\2')
  let str = tolower(str)
  return str
endfunction

function! padrino#camelize(str)
  let str = s:gsub(a:str,'/(.=)','::\u\1')
  let str = s:gsub(str,'%([_-]|<)(.)','\u\1')
  return str
endfunction

function! padrino#singularize(word)
  " Probably not worth it to be as comprehensive as Padrino but we can
  " still hit the common cases.
  let word = a:word
  if word =~? '\.js$' || word == ''
    return word
  endif
  let word = s:sub(word,'eople$','ersons')
  let word = s:sub(word,'%([Mm]ov|[aeio])@<!ies$','ys')
  let word = s:sub(word,'xe[ns]$','xs')
  let word = s:sub(word,'ves$','fs')
  let word = s:sub(word,'ss%(es)=$','sss')
  let word = s:sub(word,'s$','')
  let word = s:sub(word,'%([nrt]ch|tatus|lias)\zse$','')
  let word = s:sub(word,'%(nd|rt)\zsice$','ex')
  return word
endfunction

function! padrino#pluralize(word)
  let word = a:word
  if word == ''
    return word
  endif
  let word = s:sub(word,'[aeio]@<!y$','ie')
  let word = s:sub(word,'%(nd|rt)@<=ex$','ice')
  let word = s:sub(word,'%([osxz]|[cs]h)$','&e')
  let word = s:sub(word,'f@<!f$','ve')
  let word .= 's'
  let word = s:sub(word,'ersons$','eople')
  return word
endfunction

function! padrino#app(...)
  let root = a:0 ? a:1 : PadrinoRoot()
  " TODO: populate dynamically
  " TODO: normalize path
  return get(s:apps,root,0)
endfunction

function! padrino#buffer(...)
  return extend(extend({'#': bufnr(a:0 ? a:1 : '%')},s:buffer_prototype,'keep'),s:readable_prototype,'keep')
  endif
endfunction

function! s:buffer_app() dict abort
  if self.getvar('padrino_root') != ''
    return padrino#app(self.getvar('padrino_root'))
  else
    return 0
  endif
endfunction

function! s:readable_app() dict abort
  return self._app
endfunction

function! PadrinoRevision()
  return 1000*matchstr(g:autoloaded_padrino,'^\d\+')+matchstr(g:autoloaded_padrino,'[1-9]\d*$')
endfunction

function! PadrinoRoot()
  if exists("b:padrino_root")
    return b:padrino_root
  else
    return ""
  endif
endfunction

function! s:app_file(name)
  return extend(extend({'_app': self, '_name': a:name}, s:file_prototype,'keep'),s:readable_prototype,'keep')
endfunction

function! s:file_path() dict abort
  return self.app().path(self._name)
endfunction

function! s:file_name() dict abort
  return self._name
endfunction

function! s:buffer_number() dict abort
  return self['#']
endfunction

function! s:buffer_path() dict abort
  return s:gsub(fnamemodify(bufname(self.number()),':p'),'\\ @!','/')
endfunction

function! s:buffer_name() dict abort
  let app = self.app()
  let f = s:gsub(fnamemodify(bufname(self.number()),':p'),'\\ @!','/')
  let f = s:sub(f,'/$','')
  let sep = matchstr(f,'^[^\\/]\{3,\}\zs[\\/]')
  if sep != ""
    let f = getcwd().sep.f
  endif
  if s:startswith(tolower(f),s:gsub(tolower(app.path()),'\\ @!','/')) || f == ""
    return strpart(f,strlen(app.path())+1)
  else
    if !exists("s:path_warn")
      let s:path_warn = 1
      call s:warn("File ".f." does not appear to be under the Padrino root ".self.app().path().". Please report to the padrino.vim author!")
    endif
    return f
  endif
endfunction

function! PadrinoFilePath()
  if !exists("b:padrino_root")
    return ""
  else
    return padrino#buffer().name()
  endif
endfunction

function! PadrinoFile()
  return PadrinoFilePath()
endfunction

function! PadrinoFileType()
  if !exists("b:padrino_root")
    return ""
  else
    return padrino#buffer().type_name()
  end
endfunction

function! s:readable_calculate_file_type() dict abort
  let f = self.name()
  let e = fnamemodify(f,':e')
  let r = "-"
  let full_path = self.path()
  let nr = bufnr('^'.full_path.'$')
  if nr < 0 && exists('+shellslash') && ! &shellslash
    let nr = bufnr('^'.s:gsub(full_path,'/','\\').'$')
  endif
  if f == ""
    let r = f
  elseif nr > 0 && getbufvar(nr,'padrino_file_type') != ''
    return getbufvar(nr,'padrino_file_type')
  elseif f =~ '_controller\.rb$' || f =~ '\<app/controllers/.*\.rb$'
    if join(s:readfile(full_path,50),"\n") =~ '\<wsdl_service_name\>'
      let r = "controller-api"
    else
      let r = "controller"
    endif
  elseif f =~ '_api\.rb'
    let r = "api"
  elseif f =~ '\<test/test_helper\.rb$'
    let r = "test"
  elseif f =~ '\<spec/spec_helper\.rb$'
    let r = "spec"
  elseif f =~ '_helper\.rb$'
    let r = "helper"
  elseif f =~ '\<app/metal/.*\.rb$'
    let r = "metal"
  elseif f =~ '\<app/mailers/.*\.rb'
    let r = "mailer"
  elseif f =~ '\<app/models/' || f =~ '\<models/'
    let top = join(s:readfile(full_path,50),"\n")
    let class = matchstr(top,'\<Acti\w\w\u\w\+\%(::\h\w*\)\+\>')
    if class == "ActiveResource::Base"
      let class = "ares"
      let r = "model-ares"
    elseif class == 'ActionMailer::Base'
      let r = "mailer"
    elseif class != ''
      let class = tolower(s:gsub(class,'[^A-Z]',''))
      let r = "model-".class
    elseif f =~ '_mailer\.rb$'
      let r = "mailer"
    elseif top =~ 'include Mongoid::Document'
      let r = "model-mongoid"
    elseif top =~ '\<\%(validates_\w\+_of\|set_\%(table_name\|primary_key\)\|has_one\|has_many\|belongs_to\)\>'
      let r = "model-arb"
    else
      let r = "model"
    endif
  elseif f =~ '\<app/views/layouts\>.*\.'
    let r = "view-layout-" . e
  elseif f =~ '\<\%(app/views\|components\)/.*/_\k\+\.\k\+\%(\.\k\+\)\=$'
    let r = "view-partial-" . e
  elseif f =~ '\<app/views\>.*\.' || f =~ '\<components/.*/.*\.'.s:viewspattern().'$'
    let r = "view-" . e
  elseif f =~ '\<test/unit/.*_test\.rb$'
    let r = "test-unit"
  elseif f =~ '\<test/functional/.*_test\.rb$'
    let r = "test-functional"
  elseif f =~ '\<test/integration/.*_test\.rb$'
    let r = "test-integration"
  elseif f =~ '\<spec/lib/.*_spec\.rb$'
    let r = 'spec-lib'
  elseif f =~ '\<lib/.*\.rb$'
    let r = 'lib'
  elseif f =~ '\<spec/\w*s/.*_spec\.rb$'
    let r = s:sub(f,'.*<spec/(\w*)s/.*','spec-\1')
  elseif f =~ '\<features/.*\.feature$'
    let r = 'cucumber-feature'
  elseif f =~ '\<features/step_definitions/.*_steps\.rb$'
    let r = 'cucumber-steps'
  elseif f =~ '\<features/.*\.rb$'
    let r = 'cucumber'
  elseif f =~ '\<\%(test\|spec\)/fixtures\>'
    if e == "yml"
      let r = "fixtures-yaml"
    else
      let r = "fixtures" . (e == "" ? "" : "-" . e)
    endif
  elseif f =~ '\<test/.*_test\.rb'
    let r = "test"
  elseif f =~ '\<spec/.*_spec\.rb'
    let r = "spec"
  elseif f =~ '\<spec/support/.*\.rb'
    let r = "spec"
  elseif f =~ '\<db/migrate\>'
    let r = "db-migration"
  elseif f=~ '\<db/schema\.rb$'
    let r = "db-schema"
  elseif f =~ '\<vendor/plugins/.*/recipes/.*\.rb$' || f =~ '\.rake$' || f =~ '\<\%(Rake\|Cap\)file$' || f =~ '\<config/deploy\.rb$'
    let r = "task"
  elseif f =~ '\<log/.*\.log$'
    let r = "log"
  elseif e == "css" || e =~ "s[ac]ss" || e == "less"
    let r = "stylesheet-".e
  elseif e == "js"
    let r = "javascript"
  elseif e == "coffee"
    let r = "javascript-coffee"
  elseif e == "html"
    let r = e
  elseif f =~ '\<config/routes\>.*\.rb$'
    let r = "config-routes"
  elseif f =~ '\<config/'
    let r = "config"
  endif
  return r
endfunction

function! s:buffer_type_name(...) dict abort
  let type = getbufvar(self.number(),'padrino_cached_file_type')
  if type == ''
    let type = self.calculate_file_type()
  endif
  return call('s:match_type',[type == '-' ? '' : type] + a:000)
endfunction

function! s:readable_type_name() dict abort
  let type = self.calculate_file_type()
  return call('s:match_type',[type == '-' ? '' : type] + a:000)
endfunction

function! s:match_type(type,...)
  if a:0
    return !empty(filter(copy(a:000),'a:type =~# "^".v:val."\\%(-\\|$\\)"'))
  else
    return a:type
  endif
endfunction

function! s:app_environments() dict
  if self.cache.needs('environments')
    call self.cache.set('environments',self.relglob('config/environments/','**/*','.rb'))
  endif
  return copy(self.cache.get('environments'))
endfunction

function! s:app_default_locale() dict abort
  if self.cache.needs('default_locale')
    let candidates = map(filter(s:readfile(self.path('config/environment.rb')),'v:val =~ "^ *config.i18n.default_locale = :[\"'']\\=[A-Za-z-]\\+[\"'']\\= *$"'),'matchstr(v:val,"[A-Za-z-]\\+[\"'']\\= *$")')
    call self.cache.set('default_locale',get(candidates,0,'en'))
  endif
  return self.cache.get('default_locale')
endfunction

function! s:app_has(feature) dict
  let map = {
        \'test': 'test/',
        \'spec': 'spec/',
        \'cucumber': 'features/',
        \'sass': 'public/stylesheets/sass/',
        \'lesscss': 'app/stylesheets/',
        \'coffee': 'app/scripts/'}
  if self.cache.needs('features')
    call self.cache.set('features',{})
  endif
  let features = self.cache.get('features')
  if !has_key(features,a:feature)
    let path = get(map,a:feature,a:feature.'/')
    let features[a:feature] = isdirectory(padrino#app().path(path))
  endif
  return features[a:feature]
endfunction

" Returns the subset of ['test', 'spec', 'cucumber'] present on the app.
function! s:app_test_suites() dict
  return filter(['test','spec','cucumber'],'self.has(v:val)')
endfunction

call s:add_methods('app',['default_locale','environments','file','has','test_suites'])
call s:add_methods('file',['path','name','lines','getline'])
call s:add_methods('buffer',['app','number','path','name','lines','getline','type_name'])
call s:add_methods('readable',['app','calculate_file_type','type_name','line_count'])

" }}}1
" Ruby Execution {{{1

function! s:app_ruby_shell_command(cmd) dict abort
  if self.path() =~ '://'
    return "ruby ".a:cmd
  else
    return "ruby -C ".s:rquote(self.path())." ".a:cmd
  endif
endfunction

function! s:app_script_shell_command(cmd) dict abort
  if self.has_file('script/padrino') && a:cmd !~# '^padrino\>'
    let cmd = 'script/padrino '.a:cmd
  else
    let cmd = 'script/'.a:cmd
  endif
  return self.ruby_shell_command(cmd)
endfunction

function! s:app_background_script_command(cmd) dict abort
  let cmd = s:esccmd(self.script_shell_command(a:cmd))
  if has_key(self,'options') && has_key(self.options,'gnu_screen')
    let screen = self.options.gnu_screen
  else
    let screen = g:padrino_gnu_screen
  endif
  if has("gui_win32")
    if &shellcmdflag == "-c" && ($PATH . &shell) =~? 'cygwin'
      silent exe "!cygstart -d ".s:rquote(self.path())." ruby ".a:cmd
    else
      exe "!start ".cmd
    endif
  elseif exists("$STY") && !has("gui_running") && screen && executable("screen")
    silent exe "!screen -ln -fn -t ".s:sub(s:sub(a:cmd,'\s.*',''),'^%(script|-rcommand)/','padrino-').' '.cmd
  elseif exists("$TMUX") && !has("gui_running") && screen && executable("tmux")
    silent exe '!tmux new-window -d -n "'.s:sub(s:sub(a:cmd,'\s.*',''),'^%(script|-rcommand)/','padrino-').'" "'.cmd.'"'
  else
    exe "!".cmd
  endif
  return v:shell_error
endfunction

function! s:app_execute_script_command(cmd) dict abort
  exe '!'.s:esccmd(self.script_shell_command(a:cmd))
  return v:shell_error
endfunction

function! s:app_lightweight_ruby_eval(ruby,...) dict abort
  let def = a:0 ? a:1 : ""
  if !executable("ruby")
    return def
  endif
  let args = '-e '.s:rquote('begin; require %{rubygems}; rescue LoadError; end; begin; require %{active_support}; rescue LoadError; end; '.a:ruby)
  let cmd = self.ruby_shell_command(args)
  " If the shell is messed up, this command could cause an error message
  silent! let results = system(cmd)
  return v:shell_error == 0 ? results : def
endfunction

function! s:app_eval(ruby,...) dict abort
  let def = a:0 ? a:1 : ""
  if !executable("ruby")
    return def
  endif
  let args = "-r./config/boot -r ".s:rquote(self.path("config/environment"))." -e ".s:rquote(a:ruby)
  let cmd = self.ruby_shell_command(args)
  " If the shell is messed up, this command could cause an error message
  silent! let results = system(cmd)
  return v:shell_error == 0 ? results : def
endfunction

call s:add_methods('app', ['ruby_shell_command','script_shell_command','execute_script_command','background_script_command','lightweight_ruby_eval','eval'])

" }}}1
" Commands {{{1

function! s:prephelp()
  let fn = fnamemodify(s:file,':h:h').'/doc/'
  if filereadable(fn.'padrino.txt')
    if !filereadable(fn.'tags') || getftime(fn.'tags') <= getftime(fn.'padrino.txt')
      silent! helptags `=fn`
    endif
  endif
endfunction

function! PadrinoHelpCommand(...)
  call s:prephelp()
  let topic = a:0 ? a:1 : ""
  if topic == "" || topic == "-"
    return "help padrino"
  elseif topic =~ '^g:'
    return "help ".topic
  elseif topic =~ '^-'
    return "help padrino".topic
  else
    return "help padrino-".topic
  endif
endfunction

function! s:BufCommands()
  call s:BufFinderCommands()
  call s:BufNavCommands()
  call s:BufScriptWrappers()
  command! -buffer -bar -nargs=? -bang -count -complete=customlist,s:Complete_rake    Rake     :call s:Rake(<bang>0,!<count> && <line1> ? -1 : <count>,<q-args>)
  command! -buffer -bar -nargs=? -bang -range -complete=customlist,s:Complete_preview Rpreview :call s:Preview(<bang>0,<line1>,<q-args>)
  command! -buffer -bar -nargs=? -bang -complete=customlist,s:Complete_environments   Rlog     :call s:Log(<bang>0,<q-args>)
  command! -buffer -bar -nargs=* -bang -complete=customlist,s:Complete_set            Rset     :call s:Set(<bang>0,<f-args>)
  command! -buffer -bar -nargs=0 Rtags       :call padrino#app().tags_command()
  " Embedding all this logic directly into the command makes the error
  " messages more concise.
  command! -buffer -bar -nargs=? -bang Rdoc  :
        \ if <bang>0 || <q-args> =~ "^\\([:'-]\\|g:\\)" |
        \   exe PadrinoHelpCommand(<q-args>) |
        \ else | call s:Doc(<bang>0,<q-args>) | endif
  command! -buffer -bar -nargs=0 -bang Rrefresh :if <bang>0|unlet! g:autoloaded_padrino|source `=s:file`|endif|call s:Refresh(<bang>0)
  if exists(":NERDTree")
    command! -buffer -bar -nargs=? -complete=customlist,s:Complete_cd Rtree :NERDTree `=padrino#app().path(<f-args>)`
  endif
  if exists("g:loaded_dbext")
    command! -buffer -bar -nargs=? -complete=customlist,s:Complete_environments Rdbext  :call s:BufDatabase(2,<q-args>)|let b:dbext_buffer_defaulted = 1
  endif
  let ext = expand("%:e")
  if ext =~ s:viewspattern()
    " TODO: complete controller names with trailing slashes here
    command! -buffer -bar -bang -nargs=? -range -complete=customlist,s:controllerList Rextract :<line1>,<line2>call s:Extract(<bang>0,<f-args>)
  endif
  if PadrinoFilePath() =~ '\<db/migrate/.*\.rb$'
    command! -buffer -bar                 Rinvert  :call s:Invert(<bang>0)
  endif
endfunction

function! s:Doc(bang, string)
  if a:string != ""
    if exists("g:padrino_search_url")
      let query = substitute(a:string,'[^A-Za-z0-9_.~-]','\="%".printf("%02X",char2nr(submatch(0)))','g')
      let url = printf(g:padrino_search_url, query)
    else
      return s:error("specify a g:padrino_search_url with %s for a query placeholder")
    endif
  elseif isdirectory(padrino#app().path("doc/api/classes"))
    let url = padrino#app().path("/doc/api/index.html")
  elseif s:getpidfor("0.0.0.0","8808") > 0
    let url = "http://localhost:8808"
  else
    let url = "http://api.rubyonpadrino.org"
  endif
  call s:initOpenURL()
  if exists(":OpenURL")
    exe "OpenURL ".s:escarg(url)
  else
    return s:error("No :OpenURL command found")
  endif
endfunction

function! s:Log(bang,arg)
  if a:arg == ""
    let lf = "log/".s:environment().".log"
  else
    let lf = "log/".a:arg.".log"
  endif
  let size = getfsize(padrino#app().path(lf))
  if size >= 1048576
    call s:warn("Log file is ".((size+512)/1024)."KB.  Consider :Rake log:clear")
  endif
  if a:bang
    exe "cgetfile ".lf
    clast
  else
    if exists(":Tail")
      Tail  `=padrino#app().path(lf)`
    else
      pedit `=padrino#app().path(lf)`
    endif
  endif
endfunction

function! padrino#new_app_command(bang,...)
  if a:0 == 0
    let msg = "padrino.vim ".g:autoloaded_padrino
    if a:bang && exists('b:padrino_root') && padrino#buffer().type_name() == ''
      echo msg." (Padrino)"
    elseif a:bang && exists('b:padrino_root')
      echo msg." (Padrino-".padrino#buffer().type_name().")"
    elseif a:bang
      echo msg
    else
      !padrino
    endif
    return
  endif
  let dir = ""
  if a:1 !~ '^-' && a:1 !=# 'new'
    let dir = a:1
  elseif a:{a:0} =~ '[\/]'
    let dir = a:{a:0}
  else
    let dir = a:1
  endif
  let str = ""
  let c = 1
  while c <= a:0
    let str .= " " . s:rquote(expand(a:{c}))
    let c += 1
  endwhile
  let dir = expand(dir)
  let append = ""
  if a:bang
    let append .= " --force"
  endif
  exe "!padrino".append.str
  if filereadable(dir."/".g:padrino_default_file)
    edit `=dir.'/'.g:padrino_default_file`
  endif
endfunction

function! s:app_tags_command() dict
  if exists("g:Tlist_Ctags_Cmd")
    let cmd = g:Tlist_Ctags_Cmd
  elseif executable("exuberant-ctags")
    let cmd = "exuberant-ctags"
  elseif executable("ctags-exuberant")
    let cmd = "ctags-exuberant"
  elseif executable("ctags")
    let cmd = "ctags"
  elseif executable("ctags.exe")
    let cmd = "ctags.exe"
  else
    return s:error("ctags not found")
  endif
  exe '!'.cmd.' -f '.s:escarg(self.path("tmp/tags")).' -R --langmap="ruby:+.rake.builder.rjs" '.g:padrino_ctags_arguments.' '.s:escarg(self.path())
endfunction

call s:add_methods('app',['tags_command'])

function! s:Refresh(bang)
  if exists("g:rubycomplete_padrino") && g:rubycomplete_padrino && has("ruby") && exists('g:rubycomplete_completions')
    silent! ruby ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord)
    silent! ruby if defined?(ActiveSupport::Dependencies); ActiveSupport::Dependencies.clear; elsif defined?(Dependencies); Dependencies.clear; end
    if a:bang
      silent! ruby ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)
    endif
  endif
  call padrino#app().cache.clear()
  silent doautocmd User BufLeavePadrino
  if a:bang
    for key in keys(s:apps)
      if type(s:apps[key]) == type({})
        call s:apps[key].cache.clear()
      endif
      call extend(s:apps[key],filter(copy(s:app_prototype),'type(v:val) == type(function("tr"))'),'force')
    endfor
  endif
  let i = 1
  let max = bufnr('$')
  while i <= max
    let rr = getbufvar(i,"padrino_root")
    if rr != ""
      call setbufvar(i,"padrino_refresh",1)
    endif
    let i += 1
  endwhile
  silent doautocmd User BufEnterPadrino
endfunction

function! s:RefreshBuffer()
  if exists("b:padrino_refresh") && b:padrino_refresh
    let oldroot = b:padrino_root
    unlet! b:padrino_root
    let b:padrino_refresh = 0
    call PadrinoBufInit(oldroot)
    unlet! b:padrino_refresh
  endif
endfunction

" }}}1
" Rake {{{1

function! s:app_rake_tasks() dict
  if self.cache.needs('rake_tasks')
    call s:push_chdir()
    try
      let lines = split(system("rake -T"),"\n")
    finally
      call s:pop_command()
    endtry
    if v:shell_error != 0
      return []
    endif
    call map(lines,'matchstr(v:val,"^rake\\s\\+\\zs\\S*")')
    call filter(lines,'v:val != ""')
    call self.cache.set('rake_tasks',lines)
  endif
  return self.cache.get('rake_tasks')
endfunction

call s:add_methods('app', ['rake_tasks'])

let s:efm_backtrace='%D(in\ %f),'
      \.'%\\s%#from\ %f:%l:%m,'
      \.'%\\s%#from\ %f:%l:,'
      \.'%\\s#{PADRINO_ROOT}/%f:%l:\ %#%m,'
      \.'%\\s%##\ %f:%l:%m,'
      \.'%\\s%#[%f:%l:\ %#%m,'
      \.'%\\s%#%f:%l:\ %#%m,'
      \.'%\\s%#%f:%l:,'
      \.'%m\ [%f:%l]:'

function! s:makewithruby(arg,bang,...)
  let old_make = &makeprg
  try
    let &l:makeprg = padrino#app().ruby_shell_command(a:arg)
    exe 'make'.(a:bang ? '!' : '')
    if !a:bang
      cwindow
    endif
  finally
    let &l:makeprg = old_make
  endtry
endfunction

function! s:Rake(bang,lnum,arg)
  let self = padrino#app()
  let lnum = a:lnum < 0 ? 0 : a:lnum
  let old_makeprg = &l:makeprg
  let old_errorformat = &l:errorformat
  try
    if &l:makeprg !~# 'rake'
      let &l:makeprg = 'rake'
    endif
    let &l:errorformat = s:efm_backtrace
    let arg = a:arg
    if &filetype == "ruby" && arg == '' && g:padrino_modelines
      let mnum = s:lastmethodline(lnum)
      let str = getline(mnum)."\n".getline(mnum+1)."\n".getline(mnum+2)."\n"
      let pat = '\s\+\zs.\{-\}\ze\%(\n\|\s\s\|#{\@!\|$\)'
      let mat = matchstr(str,'#\s*rake'.pat)
      let mat = s:sub(mat,'\s+$','')
      if mat != ""
        let arg = mat
      endif
    endif
    if arg == ''
      let opt = s:getopt('task','bl')
      if opt != ''
        let arg = opt
      else
        let arg = padrino#buffer().default_rake_task(lnum)
      endif
    endif
    if !has_key(self,'options') | let self.options = {} | endif
    if arg == '-'
      let arg = get(self.options,'last_rake_task','')
    endif
    let self.options['last_rake_task'] = arg
    let withrubyargs = '-r ./config/boot -r '.s:rquote(self.path('config/environment')).' -e "puts \%((in \#{Dir.getwd}))" '
    if arg =~# '^notes\>'
      let &l:errorformat = '%-P%f:,\ \ *\ [%*[\ ]%l]\ [%t%*[^]]] %m,\ \ *\ [%*[\ ]%l] %m,%-Q'
      " %D to chdir is apparently incompatible with %P multiline messages
      call s:push_chdir(1)
      exe 'make! '.arg
      call s:pop_command()
      if !a:bang
        cwindow
      endif
    elseif arg =~# '^\%(stats\|routes\|secret\|time:zones\|db:\%(charset\|collation\|fixtures:identify\>.*\|migrate:status\|version\)\)\%([: ]\|$\)'
      let &l:errorformat = '%D(in\ %f),%+G%.%#'
      exe 'make! '.arg
      if !a:bang
        copen
      endif
    elseif arg =~ '^preview\>'
      exe (lnum == 0 ? '' : lnum).'R'.s:gsub(arg,':','/')
    elseif arg =~ '^runner:'
      let arg = s:sub(arg,'^runner:','')
      let root = matchstr(arg,'%\%(:\w\)*')
      let file = expand(root).matchstr(arg,'%\%(:\w\)*\zs.*')
      if file =~ '#.*$'
        let extra = " -- -n ".matchstr(file,'#\zs.*')
        let file = s:sub(file,'#.*','')
      else
        let extra = ''
      endif
      if self.has_file(file) || self.has_file(file.'.rb')
        call s:makewithruby(withrubyargs.'-r"'.file.'"'.extra,a:bang,file !~# '_\%(spec\|test\)\%(\.rb\)\=$')
      else
        call s:makewithruby(withrubyargs.'-e '.s:esccmd(s:rquote(arg)),a:bang)
      endif
    elseif arg == 'run' || arg == 'runner'
      call s:makewithruby(withrubyargs.'-r"'.PadrinoFilePath().'"',a:bang,PadrinoFilePath() !~# '_\%(spec\|test\)\%(\.rb\)\=$')
    elseif arg =~ '^run:'
      let arg = s:sub(arg,'^run:','')
      let arg = s:sub(arg,'^\%:h',expand('%:h'))
      let arg = s:sub(arg,'^%(\%|$|#@=)',expand('%'))
      let arg = s:sub(arg,'#(\w+[?!=]=)$',' -- -n\1')
      call s:makewithruby(withrubyargs.'-r'.arg,a:bang,arg !~# '_\%(spec\|test\)\.rb$')
    else
      exe 'make! '.arg
      if !a:bang
        cwindow
      endif
    endif
  finally
    let &l:errorformat = old_errorformat
    let &l:makeprg = old_makeprg
  endtry
endfunction

function! s:readable_default_rake_task(lnum) dict abort
  let app = self.app()
  let lnum = a:lnum < 0 ? 0 : a:lnum
  if self.getvar('&buftype') == 'quickfix'
    return '-'
  elseif self.getline(lnum) =~# '# rake '
    return matchstr(self.getline(lnum),'\C# rake \zs.*')
  elseif self.getline(self.last_method_line(lnum)-1) =~# '# rake '
    return matchstr(self.getline(self.last_method_line(lnum)-1),'\C# rake \zs.*')
  elseif self.getline(self.last_method_line(lnum)) =~# '# rake '
    return matchstr(self.getline(self.last_method_line(lnum)),'\C# rake \zs.*')
  elseif self.getline(1) =~# '# rake ' && !lnum
    return matchstr(self.getline(1),'\C# rake \zs.*')
  elseif self.type_name('config-routes')
    return 'routes'
  elseif self.type_name('fixtures-yaml') && lnum
    return "db:fixtures:identify LABEL=".self.last_method(lnum)
  elseif self.type_name('fixtures') && lnum == 0
    return "db:fixtures:load FIXTURES=".s:sub(fnamemodify(self.name(),':r'),'^.{-}/fixtures/','')
  elseif self.type_name('task')
    let mnum = self.last_method_line(lnum)
    let line = getline(mnum)
    " We can't grab the namespace so only run tasks at the start of the line
    if line =~# '^\%(task\|file\)\>'
      return self.last_method(a:lnum)
    else
      return matchstr(self.getline(1),'\C# rake \zs.*')
    endif
  elseif self.type_name('spec')
    if self.name() =~# '\<spec/spec_helper\.rb$'
      return 'spec'
    elseif lnum > 0
      return 'spec SPEC="'.self.path().'":'.lnum
    else
      return 'spec SPEC="'.self.path().'"'
    endif
  elseif self.type_name('test')
    let meth = self.last_method(lnum)
    if meth =~ '^test_'
      let call = " -n".meth.""
    else
      let call = ""
    endif
    if self.type_name('test-unit','test-functional','test-integration')
      return s:sub(s:gsub(self.type_name(),'-',':'),'unit$|functional$','&s').' TEST="'.self.path().'"'.s:sub(call,'^ ',' TESTOPTS=')
    elseif self.name() =~# '\<test/test_helper\.rb$'
      return 'test'
    else
      return 'test:recent TEST="'.self.path().'"'.s:sub(call,'^ ',' TESTOPTS=')
    endif
  elseif self.type_name('db-migration')
    let ver = matchstr(self.name(),'\<db/migrate/0*\zs\d*\ze_')
    if ver != ""
      let method = self.last_method(lnum)
      if method == "down"
        return "db:migrate:down VERSION=".ver
      elseif method == "up"
        return "db:migrate:up VERSION=".ver
      elseif lnum > 0
        return "db:migrate:down db:migrate:up VERSION=".ver
      else
        return "db:migrate VERSION=".ver
      endif
    else
      return 'db:migrate'
    endif
  elseif self.name() =~# '\<db/seeds\.rb$'
    return 'db:seed'
  elseif self.type_name('controller') && lnum
    let lm = self.last_method(lnum)
    if lm != ''
      " rake routes doesn't support ACTION... yet...
      return 'routes CONTROLLER='.self.controller_name().' ACTION='.lm
    else
      return 'routes CONTROLLER='.self.controller_name()
    endif
  elseif app.has('spec') && self.name() =~# '^app/.*\.\w\+$' && app.has_file(s:sub(self.name(),'^app/(.*)\.\w\+$','spec/\1_spec.rb'))
    return 'spec SPEC="'.fnamemodify(s:sub(self.name(),'<app/','spec/'),':p:r').'_spec.rb"'
  elseif app.has('spec') && self.name() =~# '^app/.*\.\w\+$' && app.has_file(s:sub(self.name(),'^app/(.*)$','spec/\1_spec.rb'))
    return 'spec SPEC="'.fnamemodify(s:sub(self.name(),'<app/','spec/'),':p').'_spec.rb"'
  elseif self.type_name('model')
    return 'test:units TEST="'.fnamemodify(s:sub(self.name(),'<app/models/','test/unit/'),':p:r').'_test.rb"'
  elseif self.type_name('api','mailer')
    return 'test:units TEST="'.fnamemodify(s:sub(self.name(),'<app/%(apis|mailers|models)/','test/functional/'),':p:r').'_test.rb"'
  elseif self.type_name('helper')
    return 'test:units TEST="'.fnamemodify(s:sub(self.name(),'<app/','test/unit/'),':p:r').'_test.rb"'
  elseif self.type_name('controller','helper','view')
    if self.name() =~ '\<app/' && s:controller() !~# '^\%(application\)\=$'
      return 'test:functionals TEST="'.s:escarg(app.path('test/functional/'.s:controller().'_controller_test.rb')).'"'
    else
      return 'test:functionals'
    endif
  elseif self.type_name('cucumber-feature')
    if lnum > 0
      return 'cucumber FEATURE="'.self.path().'":'.lnum
    else
      return 'cucumber FEATURE="'.self.path().'"'
    endif
  elseif self.type_name('cucumber')
    return 'cucumber'
  else
    return ''
  endif
endfunction

function! s:Complete_rake(A,L,P)
  return s:completion_filter(padrino#app().rake_tasks(),a:A)
endfunction

call s:add_methods('readable',['default_rake_task'])

" }}}1
" Preview {{{1

function! s:initOpenURL()
  if !exists(":OpenURL")
    if has("gui_mac") || has("gui_macvim") || exists("$SECURITYSESSIONID")
      command -bar -nargs=1 OpenURL :!open <args>
    elseif has("gui_win32")
      command -bar -nargs=1 OpenURL :!start cmd /cstart /b <args>
    elseif executable("sensible-browser")
      command -bar -nargs=1 OpenURL :!sensible-browser <args>
    endif
  endif
endfunction

function! s:scanlineforuris(line)
  let url = matchstr(a:line,"\\v\\C%(%(GET|PUT|POST|DELETE)\\s+|\\w+://[^/]*)/[^ \n\r\t<>\"]*[^] .,;\n\r\t<>\":]")
  if url =~ '\C^\u\+\s\+'
    let method = matchstr(url,'^\u\+')
    let url = matchstr(url,'\s\+\zs.*')
    if method !=? "GET"
      let url .= (url =~ '?' ? '&' : '?') . '_method='.tolower(method)
    endif
  endif
  if url != ""
    return [url]
  else
    return []
  endif
endfunction

function! s:readable_preview_urls(lnum) dict abort
  let urls = []
  let start = self.last_method_line(a:lnum) - 1
  while start > 0 && self.getline(start) =~ '^\s*\%(\%(-\=\|<%\)#.*\)\=$'
    let urls = s:scanlineforuris(self.getline(start)) + urls
    let start -= 1
  endwhile
  let start = 1
  while start < self.line_count() && self.getline(start) =~ '^\s*\%(\%(-\=\|<%\)#.*\)\=$'
    let urls += s:scanlineforuris(self.getline(start))
    let start += 1
  endwhile
  if has_key(self,'getvar') && self.getvar('padrino_preview') != ''
    let url += [self.getvar('padrino_preview')]
  end
  if self.name() =~ '^public/stylesheets/sass/'
    let urls = urls + [s:sub(s:sub(self.name(),'^public/stylesheets/sass/','/stylesheets/'),'\.s[ac]ss$','.css')]
  elseif self.name() =~ '^public/'
    let urls = urls + [s:sub(self.name(),'^public','')]
  elseif self.name() =~ '^app/stylesheets/'
    let urls = urls + [s:sub(s:sub(self.name(),'^app/stylesheets/','/stylesheets/'),'\.less$','.css')]
  elseif self.name() =~ '^app/scripts/'
    let urls = urls + [s:sub(s:sub(self.name(),'^app/scripts/','/javascripts/'),'\.coffee$','.js')]
  elseif self.controller_name() != '' && self.controller_name() != 'application'
    if self.type_name('controller') && self.last_method(a:lnum) != ''
      let urls += ['/'.self.controller_name().'/'.self.last_method(a:lnum).'/']
    elseif self.type_name('controller','view-layout','view-partial')
      let urls += ['/'.self.controller_name().'/']
    elseif self.type_name('view')
      let urls += ['/'.s:controller().'/'.fnamemodify(self.name(),':t:r:r').'/']
    endif
  endif
  return urls
endfunction

call s:add_methods('readable',['preview_urls'])

function! s:Preview(bang,lnum,arg)
  let root = s:getopt("root_url")
  if root == ''
    let root = s:getopt("url")
  endif
  let root = s:sub(root,'/$','')
  if a:arg =~ '://'
    let uri = a:arg
  elseif a:arg != ''
    let uri = root.'/'.s:sub(a:arg,'^/','')
  else
    let uri = get(padrino#buffer().preview_urls(a:lnum),0,'')
    let uri = root.'/'.s:sub(s:sub(uri,'^/',''),'/$','')
  endif
  call s:initOpenURL()
  if exists(':OpenURL') && !a:bang
    exe 'OpenURL '.uri
  else
    " Work around bug where URLs ending in / get handled as FTP
    let url = uri.(uri =~ '/$' ? '?' : '')
    silent exe 'pedit '.url
    wincmd w
    if &filetype == ''
      if uri =~ '\.css$'
        setlocal filetype=css
      elseif uri =~ '\.js$'
        setlocal filetype=javascript
      elseif getline(1) =~ '^\s*<'
        setlocal filetype=xhtml
      endif
    endif
    call PadrinoBufInit(padrino#app().path())
    map <buffer> <silent> q :bwipe<CR>
    wincmd p
    if !a:bang
      call s:warn("Define a :OpenURL command to use a browser")
    endif
  endif
endfunction

function! s:Complete_preview(A,L,P)
  return padrino#buffer().preview_urls(a:L =~ '^\d' ? matchstr(a:L,'^\d\+') : line('.'))
endfunction

" }}}1
" Script Wrappers {{{1

function! s:BufScriptWrappers()
  command! -buffer -bar -nargs=*       -complete=customlist,s:Complete_script   Rscript       :call padrino#app().script_command(<bang>0,<f-args>)
  command! -buffer -bar -nargs=*       -complete=customlist,s:Complete_generate Rgenerate     :call padrino#app().generate_command(<bang>0,<f-args>)
  command! -buffer -bar -nargs=*       -complete=customlist,s:Complete_destroy  Rdestroy      :call padrino#app().destroy_command(<bang>0,<f-args>)
  command! -buffer -bar -nargs=? -bang -complete=customlist,s:Complete_server   Rserver       :call padrino#app().server_command(<bang>0,<q-args>)
  command! -buffer -bang -nargs=1 -range=0 -complete=customlist,s:Complete_ruby Rrunner       :call padrino#app().runner_command(<bang>0 ? -2 : (<count>==<line2>?<count>:-1),<f-args>)
  command! -buffer       -nargs=1 -range=0 -complete=customlist,s:Complete_ruby Rp            :call padrino#app().runner_command(<count>==<line2>?<count>:-1,'p begin '.<f-args>.' end')
  command! -buffer       -nargs=1 -range=0 -complete=customlist,s:Complete_ruby Rpp           :call padrino#app().runner_command(<count>==<line2>?<count>:-1,'require %{pp}; pp begin '.<f-args>.' end')
  command! -buffer       -nargs=1 -range=0 -complete=customlist,s:Complete_ruby Ry            :call padrino#app().runner_command(<count>==<line2>?<count>:-1,'y begin '.<f-args>.' end')
endfunction

function! s:app_generators() dict
  if self.cache.needs('generators')
    let generators = self.relglob("vendor/plugins/","*/generators/*")
    let generators += self.relglob("","lib/generators/*")
    call filter(generators,'v:val =~ "/$"')
    let generators += split(glob(expand("~/.padrino/generators")."/*"),"\n")
    call map(generators,'s:sub(v:val,"^.*[\\\\/]generators[\\\\/]\\ze.","")')
    call map(generators,'s:sub(v:val,"[\\\\/]$","")')
    call self.cache.set('generators',generators)
  endif
  return sort(split(g:padrino_generators,"\n") + self.cache.get('generators'))
endfunction

function! s:app_script_command(bang,...) dict
  let str = ""
  let cmd = a:0 ? a:1 : "console"
  let c = 2
  while c <= a:0
    let str .= " " . s:rquote(a:{c})
    let c += 1
  endwhile
  if cmd ==# "plugin"
    call self.cache.clear('generators')
  endif
  if a:bang || cmd =~# 'console'
    return self.background_script_command(cmd.str)
  else
    return self.execute_script_command(cmd.str)
  endif
endfunction

function! s:app_runner_command(count,args) dict
  if a:count == -2
    return self.script_command(a:bang,"runner",a:args)
  else
    let str = self.ruby_shell_command('-r./config/boot -e "require '."'commands/runner'".'" '.s:rquote(a:args))
    let res = s:sub(system(str),'\n$','')
    if a:count < 0
      echo res
    else
      exe a:count.'put =res'
    endif
  endif
endfunction

function! s:getpidfor(bind,port)
    if has("win32") || has("win64")
      let netstat = system("netstat -anop tcp")
      let pid = matchstr(netstat,'\<'.a:bind.':'.a:port.'\>.\{-\}LISTENING\s\+\zs\d\+')
    elseif executable('lsof')
      let pid = system("lsof -i 4tcp@".a:bind.':'.a:port."|grep LISTEN|awk '{print $2}'")
      let pid = s:sub(pid,'\n','')
    else
      let pid = ""
    endif
    return pid
endfunction

function! s:app_server_command(bang,arg) dict
  let port = matchstr(a:arg,'\%(-p\|--port=\=\)\s*\zs\d\+')
  if port == ''
    let port = "3000"
  endif
  " TODO: Extract bind argument
  let bind = "0.0.0.0"
  if a:bang && executable("ruby")
    let pid = s:getpidfor(bind,port)
    if pid =~ '^\d\+$'
      echo "Killing server with pid ".pid
      if !has("win32")
        call system("ruby -e 'Process.kill(:TERM,".pid.")'")
        sleep 100m
      endif
      call system("ruby -e 'Process.kill(9,".pid.")'")
      sleep 100m
    endif
    if a:arg == "-"
      return
    endif
  endif
  if has_key(self,'options') && has_key(self.options,'gnu_screen')
    let screen = self.options.gnu_screen
  else
    let screen = g:padrino_gnu_screen
  endif
  if has("win32") || has("win64") || (exists("$STY") && !has("gui_running") && screen && executable("screen")) || (exists("$TMUX") && !has("gui_running") && screen && executable("tmux"))
    call self.background_script_command('server '.a:arg)
  else
    " --daemon would be more descriptive but lighttpd does not support it
    call self.execute_script_command('server '.a:arg." -d")
  endif
  call s:setopt('a:root_url','http://'.(bind=='0.0.0.0'?'localhost': bind).':'.port.'/')
endfunction

function! s:app_destroy_command(bang,...) dict
  if a:0 == 0
    return self.execute_script_command('destroy')
  elseif a:0 == 1
    return self.execute_script_command('destroy '.s:rquote(a:1))
  endif
  let str = ""
  let c = 1
  while c <= a:0
    let str .= " " . s:rquote(a:{c})
    let c += 1
  endwhile
  call self.execute_script_command('destroy'.str)
  call self.cache.clear('user_classes')
endfunction

function! s:app_generate_command(bang,...) dict
  if a:0 == 0
    return self.execute_script_command('generate')
  elseif a:0 == 1
    return self.execute_script_command('generate '.s:rquote(a:1))
  endif
  let cmd = join(map(copy(a:000),'s:rquote(v:val)'),' ')
  if cmd !~ '-p\>' && cmd !~ '--pretend\>'
    let execstr = self.script_shell_command('generate '.cmd.' -p -f')
    let res = system(execstr)
    let g:res = res
    let junk = '\%(\e\[[0-9;]*m\)\='
    let file = matchstr(res,junk.'\s\+\%(create\|force\)'.junk.'\s\+\zs\f\+\.rb\ze\n')
    if file == ""
      let file = matchstr(res,junk.'\s\+\%(identical\)'.junk.'\s\+\zs\f\+\.rb\ze\n')
    endif
  else
    let file = ""
  endif
  if !self.execute_script_command('generate '.cmd) && file != ''
    call self.cache.clear('user_classes')
    call self.cache.clear('features')
    if file =~ '^db/migrate/\d\d\d\d'
      let file = get(self.relglob('',s:sub(file,'\d+','[0-9]*[0-9]')),-1,file)
    endif
    edit `=self.path(file)`
  endif
endfunction

call s:add_methods('app', ['generators','script_command','runner_command','server_command','destroy_command','generate_command'])

function! s:Complete_script(ArgLead,CmdLine,P)
  let cmd = s:sub(a:CmdLine,'^\u\w*\s+','')
  if cmd !~ '^[ A-Za-z0-9_=:-]*$'
    return []
  elseif cmd =~# '^\w*$'
    return s:completion_filter(padrino#app().relglob("script/","**/*"),a:ArgLead)
  elseif cmd =~# '^\%(plugin\)\s\+'.a:ArgLead.'$'
    return s:completion_filter(["discover","list","install","update","remove","source","unsource","sources"],a:ArgLead)
  elseif cmd =~# '\%(plugin\)\s\+\%(install\|remove\)\s\+'.a:ArgLead.'$' || cmd =~ '\%(generate\|destroy\)\s\+plugin\s\+'.a:ArgLead.'$'
    return s:pluginList(a:ArgLead,a:CmdLine,a:P)
  elseif cmd =~# '^\%(generate\|destroy\)\s\+'.a:ArgLead.'$'
    return s:completion_filter(padrino#app().generators(),a:ArgLead)
  elseif cmd =~# '^\%(generate\|destroy\)\s\+\w\+\s\+'.a:ArgLead.'$'
    let target = matchstr(cmd,'^\w\+\s\+\%(\w\+:\)\=\zs\w\+\ze\s\+')
    if target =~# '^\w*controller$'
      return filter(s:controllerList(a:ArgLead,"",""),'v:val !=# "application"')
    elseif target ==# 'generator'
      return s:completion_filter(map(padrino#app().relglob('lib/generators/','*'),'s:sub(v:val,"/$","")'))
    elseif target ==# 'helper'
      return s:helperList(a:ArgLead,"","")
    elseif target ==# 'integration_test' || target ==# 'integration_spec' || target ==# 'feature'
      return s:integrationtestList(a:ArgLead,"","")
    elseif target ==# 'metal'
      return s:metalList(a:ArgLead,"","")
    elseif target ==# 'migration' || target ==# 'session_migration'
      return s:migrationList(a:ArgLead,"","")
    elseif target =~# '^\w*\%(model\|resource\)$' || target =~# '\w*scaffold\%(_controller\)\=$' || target ==# 'mailer'
      return s:modelList(a:ArgLead,"","")
    elseif target ==# 'observer'
      let observers = s:observerList("","","")
      let models = s:modelList("","","")
      if cmd =~# '^destroy\>'
        let models = []
      endif
      call filter(models,'index(observers,v:val) < 0')
      return s:completion_filter(observers + models,a:ArgLead)
    else
      return []
    endif
  elseif cmd =~# '^\%(generate\|destroy\)\s\+scaffold\s\+\w\+\s\+'.a:ArgLead.'$'
    return filter(s:controllerList(a:ArgLead,"",""),'v:val !=# "application"')
    return s:completion_filter(padrino#app().environments())
  elseif cmd =~# '^\%(console\)\s\+\(--\=\w\+\s\+\)\='.a:ArgLead."$"
    return s:completion_filter(padrino#app().environments()+["-s","--sandbox"],a:ArgLead)
  elseif cmd =~# '^\%(server\)\s\+.*-e\s\+'.a:ArgLead."$"
    return s:completion_filter(padrino#app().environments(),a:ArgLead)
  elseif cmd =~# '^\%(server\)\s\+'
    if a:ArgLead =~# '^--environment='
      return s:completion_filter(map(copy(padrino#app().environments()),'"--environment=".v:val'),a:ArgLead)
    else
      return filter(["-p","-b","-e","-m","-d","-u","-c","-h","--port=","--binding=","--environment=","--mime-types=","--daemon","--debugger","--charset=","--help"],'s:startswith(v:val,a:ArgLead)')
    endif
  endif
  return ""
endfunction

function! s:CustomComplete(A,L,P,cmd)
  let L = "Rscript ".a:cmd." ".s:sub(a:L,'^\h\w*\s+','')
  let P = a:P - strlen(a:L) + strlen(L)
  return s:Complete_script(a:A,L,P)
endfunction

function! s:Complete_server(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"server")
endfunction

function! s:Complete_console(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"console")
endfunction

function! s:Complete_generate(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"generate")
endfunction

function! s:Complete_destroy(A,L,P)
  return s:CustomComplete(a:A,a:L,a:P,"destroy")
endfunction

function! s:Complete_ruby(A,L,P)
  return s:completion_filter(padrino#app().user_classes()+["ActiveRecord::Base"],a:A)
endfunction

" }}}1
" Navigation {{{1

function! s:BufNavCommands()
  command! -buffer -bar -nargs=? -complete=customlist,s:Complete_cd Rcd   :cd `=padrino#app().path(<q-args>)`
  command! -buffer -bar -nargs=? -complete=customlist,s:Complete_cd Rlcd :lcd `=padrino#app().path(<q-args>)`
  command! -buffer -bar -nargs=* -count=1 -complete=customlist,s:Complete_find Rfind    :call s:Find(<count>,'<bang>' ,<f-args>)
  command! -buffer -bar -nargs=* -count=1 -complete=customlist,s:Complete_find REfind   :call s:Find(<count>,'E<bang>',<f-args>)
  command! -buffer -bar -nargs=* -count=1 -complete=customlist,s:Complete_find RSfind   :call s:Find(<count>,'S<bang>',<f-args>)
  command! -buffer -bar -nargs=* -count=1 -complete=customlist,s:Complete_find RVfind   :call s:Find(<count>,'V<bang>',<f-args>)
  command! -buffer -bar -nargs=* -count=1 -complete=customlist,s:Complete_find RTfind   :call s:Find(<count>,'T<bang>',<f-args>)
  command! -buffer -bar -nargs=* -count=1 -complete=customlist,s:Complete_find Rsfind   :<count>RSfind<bang> <args>
  command! -buffer -bar -nargs=* -count=1 -complete=customlist,s:Complete_find Rtabfind :<count>RTfind<bang> <args>
  command! -buffer -bar -nargs=* -bang    -complete=customlist,s:Complete_edit Redit    :call s:Edit(<count>,'<bang>' ,<f-args>)
  command! -buffer -bar -nargs=* -bang    -complete=customlist,s:Complete_edit REedit   :call s:Edit(<count>,'E<bang>',<f-args>)
  command! -buffer -bar -nargs=* -bang    -complete=customlist,s:Complete_edit RSedit   :call s:Edit(<count>,'S<bang>',<f-args>)
  command! -buffer -bar -nargs=* -bang    -complete=customlist,s:Complete_edit RVedit   :call s:Edit(<count>,'V<bang>',<f-args>)
  command! -buffer -bar -nargs=* -bang    -complete=customlist,s:Complete_edit RTedit   :call s:Edit(<count>,'T<bang>',<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_edit RDedit   :call s:Edit(<count>,'<line1>D<bang>',<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related A     :call s:Alternate('<bang>', <line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AE    :call s:Alternate('E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AS    :call s:Alternate('S<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AV    :call s:Alternate('V<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AT    :call s:Alternate('T<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AD    :call s:Alternate('D<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related AN    :call s:Related('<bang>' ,<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related R     :call s:Related('<bang>' ,<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RE    :call s:Related('E<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RS    :call s:Related('S<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RV    :call s:Related('V<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RT    :call s:Related('T<bang>',<line1>,<line2>,<count>,<f-args>)
  command! -buffer -bar -nargs=* -range=0 -complete=customlist,s:Complete_related RD    :call s:Related('D<bang>',<line1>,<line2>,<count>,<f-args>)
endfunction

function! s:djump(def)
  let def = s:sub(a:def,'^[#:]','')
  if def =~ '^\d\+$'
    exe def
  elseif def =~ '^!'
    if expand('%') !~ '://' && !isdirectory(expand('%:p:h'))
      call mkdir(expand('%:p:h'),'p')
    endif
  elseif def != ''
    let ext = matchstr(def,'\.\zs.*')
    let def = matchstr(def,'[^.]*')
    let v:errmsg = ''
    silent! exe "djump ".def
    if ext != '' && (v:errmsg == '' || v:errmsg =~ '^E387')
      let rpat = '\C^\s*\%(mail\>.*\|respond_to\)\s*\%(\<do\|{\)\s*|\zs\h\k*\ze|'
      let end = s:endof(line('.'))
      let rline = search(rpat,'',end)
      if rline > 0
        let variable = matchstr(getline(rline),rpat)
        let success = search('\C^\s*'.variable.'\s*\.\s*\zs'.ext.'\>','',end)
        if !success
          silent! exe "djump ".def
        endif
      endif
    endif
  endif
endfunction

function! s:Find(count,cmd,...)
  let str = ""
  if a:0
    let i = 1
    while i < a:0
      let str .= s:escarg(a:{i}) . " "
      let i += 1
    endwhile
    let file = a:{i}
    let tail = matchstr(file,'[#!].*$\|:\d*\%(:in\>.*\)\=$')
    if tail != ""
      let file = s:sub(file,'[#!].*$|:\d*%(:in>.*)=$','')
    endif
    if file != ""
      let file = s:PadrinoIncludefind(file)
    endif
  else
    let file = s:PadrinoFind()
    let tail = ""
  endif
  call s:findedit((a:count==1?'' : a:count).a:cmd,file.tail,str)
endfunction

function! s:Edit(count,cmd,...)
  if a:0
    let str = ""
    let i = 1
    while i < a:0
      let str .= "`=a:".i."` "
      let i += 1
    endwhile
    let file = a:{i}
    call s:findedit(s:editcmdfor(a:cmd),file,str)
  else
    exe s:editcmdfor(a:cmd)
  endif
endfunction

function! s:fuzzyglob(arg)
  return s:gsub(s:gsub(a:arg,'[^/.]','[&]*'),'%(/|^)\.@!|\.','&*')
endfunction

function! s:Complete_find(ArgLead, CmdLine, CursorPos)
  let paths = s:pathsplit(&l:path)
  let seen = {}
  for path in paths
    if s:startswith(path,padrino#app().path()) && path !~ '[][*]'
      let path = path[strlen(padrino#app().path()) + 1 : ]
      for file in padrino#app().relglob(path == '' ? '' : path.'/',s:fuzzyglob(padrino#underscore(a:ArgLead)), a:ArgLead =~# '\u' ? '.rb' : '')
        let seen[file] = 1
      endfor
    endif
  endfor
  let results = sort(map(keys(seen),'s:sub(v:val,"[.]rb$","")'))
  return s:autocamelize(results,a:ArgLead)
endfunction

function! s:Complete_edit(ArgLead, CmdLine, CursorPos)
  return s:completion_filter(padrino#app().relglob("",s:fuzzyglob(a:ArgLead)),a:ArgLead)
endfunction

function! s:Complete_cd(ArgLead, CmdLine, CursorPos)
  let all = padrino#app().relglob("",a:ArgLead."*")
  call filter(all,'v:val =~ "/$"')
  return filter(all,'s:startswith(v:val,a:ArgLead)')
endfunction

function! PadrinoIncludeexpr()
  " Is this foolproof?
  if mode() =~ '[iR]' || expand("<cfile>") != v:fname
    return s:PadrinoIncludefind(v:fname)
  else
    return s:PadrinoIncludefind(v:fname,1)
  endif
endfunction

function! s:linepeak()
  let line = getline(line("."))
  let line = s:sub(line,'^(.{'.col(".").'}).*','\1')
  let line = s:sub(line,'([:"'."'".']|\%[qQ]=[[({<])=\f*$','')
  return line
endfunction

function! s:matchcursor(pat)
  let line = getline(".")
  let lastend = 0
  while lastend >= 0
    let beg = match(line,'\C'.a:pat,lastend)
    let end = matchend(line,'\C'.a:pat,lastend)
    if beg < col(".") && end >= col(".")
      return matchstr(line,'\C'.a:pat,lastend)
    endif
    let lastend = end
  endwhile
  return ""
endfunction

function! s:findit(pat,repl)
  let res = s:matchcursor(a:pat)
  if res != ""
    return substitute(res,'\C'.a:pat,a:repl,'')
  else
    return ""
  endif
endfunction

function! s:findamethod(func,repl)
  return s:findit('\s*\<\%('.a:func.'\)\s*(\=\s*[@:'."'".'"]\(\f\+\)\>.\=',a:repl)
endfunction

function! s:findasymbol(sym,repl)
  return s:findit('\s*\%(:\%('.a:sym.'\)\s*=>\|\<'.a:sym.':\)\s*(\=\s*[@:'."'".'"]\(\f\+\)\>.\=',a:repl)
endfunction

function! s:findfromview(func,repl)
  "                     (   )            (           )                      ( \1  )                   (      )
  return s:findit('\s*\%(<%\)\==\=\s*\<\%('.a:func.'\)\s*(\=\s*[@:'."'".'"]\(\f\+\)\>['."'".'"]\=\s*\%(%>\s*\)\=',a:repl)
endfunction

function! s:PadrinoFind()
  if filereadable(expand("<cfile>"))
    return expand("<cfile>")
  endif

  " UGH
  let buffer = padrino#buffer()
  let format = s:format('html')

  let res = s:findit('\v\s*<require\s*\(=\s*File.dirname\(__FILE__\)\s*\+\s*[:'."'".'"](\f+)>.=',expand('%:h').'/\1')
  if res != ""|return res.(fnamemodify(res,':e') == '' ? '.rb' : '')|endif

  let res = s:findit('\v<File.dirname\(__FILE__\)\s*\+\s*[:'."'".'"](\f+)>['."'".'"]=',expand('%:h').'\1')
  if res != ""|return res|endif

  let res = padrino#underscore(s:findit('\v\s*<%(include|extend)\(=\s*<([[:alnum:]_:]+)>','\1'))
  if res != ""|return res.".rb"|endif

  let res = s:findamethod('require','\1')
  if res != ""|return res.(fnamemodify(res,':e') == '' ? '.rb' : '')|endif

  let res = s:findamethod('belongs_to\|has_one\|composed_of\|validates_associated\|scaffold','app/models/\1.rb')
  if res != ""|return res|endif

  let res = padrino#singularize(s:findamethod('has_many\|has_and_belongs_to_many','app/models/\1'))
  if res != ""|return res.".rb"|endif

  let res = padrino#singularize(s:findamethod('create_table\|change_table\|drop_table\|add_column\|rename_column\|remove_column\|add_index','app/models/\1'))
  if res != ""|return res.".rb"|endif

  let res = padrino#singularize(s:findasymbol('through','app/models/\1'))
  if res != ""|return res.".rb"|endif

  let res = s:findamethod('fixtures','fixtures/\1')
  if res != ""
    return PadrinoFilePath() =~ '\<spec/' ? 'spec/'.res : res
  endif

  let res = s:findamethod('\%(\w\+\.\)\=resources','app/controllers/\1_controller.rb')
  if res != ""|return res|endif

  let res = s:findamethod('\%(\w\+\.\)\=resource','app/controllers/\1')
  if res != ""|return padrino#pluralize(res)."_controller.rb"|endif

  let res = s:findasymbol('to','app/controllers/\1')
  if res =~ '#'|return s:sub(res,'#','_controller.rb#')|endif

  let res = s:findamethod('root\s*\%(:to\s*=>\|\<to:\)\s*','app/controllers/\1')
  if res =~ '#'|return s:sub(res,'#','_controller.rb#')|endif

  let res = s:findamethod('\%(match\|get\|put\|post\|delete\|redirect\)\s*(\=\s*[:''"][^''"]*[''"]\=\s*\%(\%(,\s*:to\s*\)\==>\|,\s*to:\)\s*','app/controllers/\1')
  if res =~ '#'|return s:sub(res,'#','_controller.rb#')|endif

  let res = s:findamethod('layout','\=s:findlayout(submatch(1))')
  if res != ""|return res|endif

  let res = s:findasymbol('layout','\=s:findlayout(submatch(1))')
  if res != ""|return res|endif

  let res = s:findamethod('helper','app/helpers/\1_helper.rb')
  if res != ""|return res|endif

  let res = s:findasymbol('controller','app/controllers/\1_controller.rb')
  if res != ""|return res|endif

  let res = s:findasymbol('action','\1')
  if res != ""|return res|endif

  let res = s:findasymbol('template','app/views/\1')
  if res != ""|return res|endif

  let res = s:sub(s:sub(s:findasymbol('partial','\1'),'^/',''),'[^/]+$','_&')
  if res != ""|return res."\n".s:findview(res)|endif

  let res = s:sub(s:sub(s:findfromview('render\s*(\=\s*\%(:partial\s\+=>\|partial:\)\s*','\1'),'^/',''),'[^/]+$','_&')
  if res != ""|return res."\n".s:findview(res)|endif

  let res = s:findamethod('render\>\s*\%(:\%(template\|action\)\s\+=>\|template:\|action:\)\s*','\1.'.format.'\n\1')
  if res != ""|return res|endif

  let res = s:sub(s:findfromview('render','\1'),'^/','')
  if buffer.type_name('view') | let res = s:sub(res,'[^/]+$','_&') | endif
  if res != ""|return res."\n".s:findview(res)|endif

  let res = s:findamethod('redirect_to\s*(\=\s*\%\(:action\s\+=>\|\<action:\)\s*','\1')
  if res != ""|return res|endif

  let res = s:findfromview('stylesheet_link_tag','public/stylesheets/\1')
  if res != '' && fnamemodify(res, ':e') == '' " Append the default extension iff the filename doesn't already contains an extension
    let res .= '.css'
  end
  if res != ""|return res|endif

  let res = s:sub(s:findfromview('javascript_include_tag','public/javascripts/\1'),'/defaults>','/application')
  if res != '' && fnamemodify(res, ':e') == '' " Append the default extension iff the filename doesn't already contains an extension
    let res .= '.js'
  end
  if res != ""|return res|endif

  if buffer.type_name('controller')
    let contr = s:controller()
    let view = s:findit('\s*\<def\s\+\(\k\+\)\>(\=','/\1')
    let res = s:findview(contr.'/'.view)
    if res != ""|return res|endif
  endif

  let old_isfname = &isfname
  try
    set isfname=@,48-57,/,-,_,:,#
    " TODO: grab visual selection in visual mode
    let cfile = expand("<cfile>")
  finally
    let &isfname = old_isfname
  endtry
  let res = s:PadrinoIncludefind(cfile,1)
  return res
endfunction

function! s:app_named_route_file(route) dict
  call self.route_names()
  if self.cache.has("named_routes") && has_key(self.cache.get("named_routes"),a:route)
    return self.cache.get("named_routes")[a:route]
  endif
  return ""
endfunction

function! s:app_route_names() dict
  if self.cache.needs("named_routes")
    let exec = "ActionController::Routing::Routes.named_routes.each {|n,r| puts %{#{n} app/controllers/#{r.requirements[:controller]}_controller.rb##{r.requirements[:action]}}}"
    let string = self.eval(exec)
    let routes = {}
    for line in split(string,"\n")
      let route = split(line," ")
      let name = route[0]
      let routes[name] = route[1]
    endfor
    call self.cache.set("named_routes",routes)
  endif

  return keys(self.cache.get("named_routes"))
endfunction

call s:add_methods('app', ['route_names','named_route_file'])

function! PadrinoNamedRoutes()
  return padrino#app().route_names()
endfunction

function! s:PadrinoIncludefind(str,...)
  if a:str ==# "ApplicationController"
    return "application_controller.rb\napp/controllers/application.rb"
  elseif a:str ==# "Test::Unit::TestCase"
    return "test/unit/testcase.rb"
  endif
  let str = a:str
  if a:0 == 1
    " Get the text before the filename under the cursor.
    " We'll cheat and peak at this in a bit
    let line = s:linepeak()
    let line = s:sub(line,'([:"'."'".']|\%[qQ]=[[({<])=\f*$','')
  else
    let line = ""
  endif
  let str = s:sub(str,'^\s*','')
  let str = s:sub(str,'\s*$','')
  let str = s:sub(str,'^:=[:@]','')
  let str = s:sub(str,':0x\x+$','') " For #<Object:0x...> style output
  let str = s:gsub(str,"[\"']",'')
  if line =~# '\<\(require\|load\)\s*(\s*$'
    return str
  elseif str =~# '^\l\w*#\w\+$'
    return 'app/controllers/'.s:sub(str,'#','_controller.rb#')
  endif
  let str = padrino#underscore(str)
  let fpat = '\(\s*\%("\f*"\|:\f*\|'."'\\f*'".'\)\s*,\s*\)*'
  if a:str =~# '\u'
    " Classes should always be in .rb files
    let str .= '.rb'
  elseif line =~# ':partial\s*=>\s*'
    let str = s:sub(str,'[^/]+$','_&')
    let str = s:findview(str)
  elseif line =~# '\<layout\s*(\=\s*' || line =~# ':layout\s*=>\s*'
    let str = s:findview(s:sub(str,'^/=','layouts/'))
  elseif line =~# ':controller\s*=>\s*'
    let str = 'app/controllers/'.str.'_controller.rb'
  elseif line =~# '\<helper\s*(\=\s*'
    let str = 'app/helpers/'.str.'_helper.rb'
  elseif line =~# '\<fixtures\s*(\='.fpat
    if PadrinoFilePath() =~# '\<spec/'
      let str = s:sub(str,'^/@!','spec/fixtures/')
    else
      let str = s:sub(str,'^/@!','test/fixtures/')
    endif
  elseif line =~# '\<stylesheet_\(link_tag\|path\)\s*(\='.fpat
    let str = s:sub(str,'^/@!','/stylesheets/')
    if str != '' && fnamemodify(str, ':e') == ''
      let str .= '.css'
    endif
  elseif line =~# '\<javascript_\(include_tag\|path\)\s*(\='.fpat
    if str ==# "defaults"
      let str = "application"
    endif
    let str = s:sub(str,'^/@!','/javascripts/')
    if str != '' && fnamemodify(str, ':e') == ''
      let str .= '.js'
    endif
  elseif line =~# '\<\(has_one\|belongs_to\)\s*(\=\s*'
    let str = 'app/models/'.str.'.rb'
  elseif line =~# '\<has_\(and_belongs_to_\)\=many\s*(\=\s*'
    let str = 'app/models/'.padrino#singularize(str).'.rb'
  elseif line =~# '\<def\s\+' && expand("%:t") =~# '_controller\.rb'
    let str = s:findview(str)
  elseif str =~# '_\%(path\|url\)$' || (line =~# ':as\s*=>\s*$' && padrino#buffer().type_name('config-routes'))
    if line !~# ':as\s*=>\s*$'
      let str = s:sub(str,'_%(path|url)$','')
      let str = s:sub(str,'^hash_for_','')
    endif
    let file = padrino#app().named_route_file(str)
    if file == ""
      let str = s:sub(str,'^formatted_','')
      if str =~# '^\%(new\|edit\)_'
        let str = 'app/controllers/'.s:sub(padrino#pluralize(str),'^(new|edit)_(.*)','\2_controller.rb#\1')
      elseif str ==# padrino#singularize(str)
        " If the word can't be singularized, it's probably a link to the show
        " method.  We should verify by checking for an argument, but that's
        " difficult the way things here are currently structured.
        let str = 'app/controllers/'.padrino#pluralize(str).'_controller.rb#show'
      else
        let str = 'app/controllers/'.str.'_controller.rb#index'
      endif
    else
      let str = file
    endif
  elseif str !~ '/'
    " If we made it this far, we'll risk making it singular.
    let str = padrino#singularize(str)
    let str = s:sub(str,'_id$','')
  endif
  if str =~ '^/' && !filereadable(str)
    let str = s:sub(str,'^/','')
  endif
  if str =~# '^lib/' && !filereadable(str)
    let str = s:sub(str,'^lib/','')
  endif
  return str
endfunction

" }}}1
" File Finders {{{1

function! s:addfilecmds(type)
  let l = s:sub(a:type,'^.','\l&')
  let cmds = 'ESVTD '
  let cmd = ''
  while cmds != ''
    let cplt = " -complete=customlist,".s:sid.l."List"
    exe "command! -buffer -bar ".(cmd == 'D' ? '-range=0 ' : '')."-nargs=*".cplt." R".cmd.l." :call s:".l.'Edit("'.(cmd == 'D' ? '<line1>' : '').cmd.'<bang>",<f-args>)'
    let cmd = strpart(cmds,0,1)
    let cmds = strpart(cmds,1)
  endwhile
endfunction

function! s:BufFinderCommands()
  command! -buffer -bar -nargs=+ Rnavcommand :call s:Navcommand(<bang>0,<f-args>)
  call s:addfilecmds("metal")
  call s:addfilecmds("model")
  call s:addfilecmds("view")
  call s:addfilecmds("controller")
  call s:addfilecmds("mailer")
  call s:addfilecmds("migration")
  call s:addfilecmds("observer")
  call s:addfilecmds("helper")
  call s:addfilecmds("layout")
  call s:addfilecmds("fixtures")
  call s:addfilecmds("locale")
  if padrino#app().has('test') || padrino#app().has('spec')
    call s:addfilecmds("unittest")
    call s:addfilecmds("functionaltest")
  endif
  if padrino#app().has('test') || padrino#app().has('spec') || padrino#app().has('cucumber')
    call s:addfilecmds("integrationtest")
  endif
  if padrino#app().has('spec')
    call s:addfilecmds("spec")
  endif
  call s:addfilecmds("stylesheet")
  call s:addfilecmds("javascript")
  call s:addfilecmds("plugin")
  call s:addfilecmds("task")
  call s:addfilecmds("lib")
  call s:addfilecmds("environment")
  call s:addfilecmds("initializer")
endfunction

function! s:completion_filter(results,A)
  let results = sort(type(a:results) == type("") ? split(a:results,"\n") : copy(a:results))
  call filter(results,'v:val !~# "\\~$"')
  let filtered = filter(copy(results),'s:startswith(v:val,a:A)')
  if !empty(filtered) | return filtered | endif
  let regex = s:gsub(a:A,'[^/]','[&].*')
  let filtered = filter(copy(results),'v:val =~# "^".regex')
  if !empty(filtered) | return filtered | endif
  let regex = s:gsub(a:A,'.','[&].*')
  let filtered = filter(copy(results),'v:val =~# regex')
  return filtered
endfunction

function! s:autocamelize(files,test)
  if a:test =~# '^\u'
    return s:completion_filter(map(copy(a:files),'padrino#camelize(v:val)'),a:test)
  else
    return s:completion_filter(a:files,a:test)
  endif
endfunction

function! s:app_relglob(path,glob,...) dict
  if exists("+shellslash") && ! &shellslash
    let old_ss = &shellslash
    let &shellslash = 1
  endif
  let path = a:path
  if path !~ '^/' && path !~ '^\w:'
    let path = self.path(path)
  endif
  let suffix = a:0 ? a:1 : ''
  let full_paths = split(glob(path.a:glob.suffix),"\n")
  let relative_paths = []
  for entry in full_paths
    if suffix == '' && isdirectory(entry) && entry !~ '/$'
      let entry .= '/'
    endif
    let relative_paths += [entry[strlen(path) : -strlen(suffix)-1]]
  endfor
  if exists("old_ss")
    let &shellslash = old_ss
  endif
  return relative_paths
endfunction

call s:add_methods('app', ['relglob'])

function! s:relglob(...)
  return join(call(padrino#app().relglob,a:000,padrino#app()),"\n")
endfunction

function! s:helperList(A,L,P)
  return s:autocamelize(padrino#app().relglob("app/helpers/","**/*","_helper.rb"),a:A)
endfunction

function! s:controllerList(A,L,P)
  let con = padrino#app().relglob("app/controllers/","**/*",".rb")
  call map(con,'s:sub(v:val,"_controller$","")')
  return s:autocamelize(con,a:A)
endfunction

function! s:mailerList(A,L,P)
  return s:autocamelize(padrino#app().relglob("app/mailers/","**/*",".rb"),a:A)
endfunction

function! s:viewList(A,L,P)
  let c = s:controller(1)
  let top = padrino#app().relglob("app/views/",s:fuzzyglob(a:A))
  call filter(top,'v:val !~# "\\~$"')
  if c != '' && a:A !~ '/'
    let local = padrino#app().relglob("app/views/".c."/","*.*[^~]")
    return s:completion_filter(local+top,a:A)
  endif
  return s:completion_filter(top,a:A)
endfunction

function! s:layoutList(A,L,P)
  return s:completion_filter(padrino#app().relglob("app/views/layouts/","*"),a:A)
endfunction

function! s:stylesheetList(A,L,P)
  let list = padrino#app().relglob('public/stylesheets/','**/*','.css')
  if padrino#app().has('sass')
    call extend(list,padrino#app().relglob('public/stylesheets/sass/','**/*','.s?ss'))
    call s:uniq(list)
  endif
  return s:completion_filter(list,a:A)
endfunction

function! s:javascriptList(A,L,P)
  return s:completion_filter(padrino#app().relglob("public/javascripts/","**/*",".js"),a:A)
endfunction

function! s:metalList(A,L,P)
  return s:autocamelize(padrino#app().relglob("app/metal/","**/*",".rb"),a:A)
endfunction

function! s:modelList(A,L,P)
  let models = padrino#app().relglob("app/models/","**/*",".rb")
  call filter(models,'v:val !~# "_observer$"')
  return s:autocamelize(models,a:A)
endfunction

function! s:observerList(A,L,P)
  return s:autocamelize(padrino#app().relglob("app/models/","**/*","_observer.rb"),a:A)
endfunction

function! s:fixturesList(A,L,P)
  return s:completion_filter(padrino#app().relglob("test/fixtures/","**/*")+padrino#app().relglob("spec/fixtures/","**/*"),a:A)
endfunction

function! s:localeList(A,L,P)
  return s:completion_filter(padrino#app().relglob("config/locales/","**/*"),a:A)
endfunction

function! s:migrationList(A,L,P)
  if a:A =~ '^\d'
    let migrations = padrino#app().relglob("db/migrate/",a:A."[0-9_]*",".rb")
    return map(migrations,'matchstr(v:val,"^[0-9]*")')
  else
    let migrations = padrino#app().relglob("db/migrate/","[0-9]*[0-9]_*",".rb")
    call map(migrations,'s:sub(v:val,"^[0-9]*_","")')
    return s:autocamelize(migrations,a:A)
  endif
endfunction

function! s:unittestList(A,L,P)
  let found = []
  if padrino#app().has('test')
    let found += padrino#app().relglob("test/unit/","**/*","_test.rb")
  endif
  if padrino#app().has('spec')
    let found += padrino#app().relglob("spec/models/","**/*","_spec.rb")
  endif
  return s:autocamelize(found,a:A)
endfunction

function! s:functionaltestList(A,L,P)
  let found = []
  if padrino#app().has('test')
    let found += padrino#app().relglob("test/functional/","**/*","_test.rb")
  endif
  if padrino#app().has('spec')
    let found += padrino#app().relglob("spec/controllers/","**/*","_spec.rb")
    let found += padrino#app().relglob("spec/mailers/","**/*","_spec.rb")
  endif
  return s:autocamelize(found,a:A)
endfunction

function! s:integrationtestList(A,L,P)
  if a:A =~# '^\u'
    return s:autocamelize(padrino#app().relglob("test/integration/","**/*","_test.rb"),a:A)
  endif
  let found = []
  if padrino#app().has('test')
    let found += padrino#app().relglob("test/integration/","**/*","_test.rb")
  endif
  if padrino#app().has('spec')
    let found += padrino#app().relglob("spec/requests/","**/*","_spec.rb")
    let found += padrino#app().relglob("spec/integration/","**/*","_spec.rb")
  endif
  if padrino#app().has('cucumber')
    let found += padrino#app().relglob("features/","**/*",".feature")
  endif
  return s:completion_filter(found,a:A)
endfunction

function! s:specList(A,L,P)
  return s:completion_filter(padrino#app().relglob("spec/","**/*","_spec.rb"),a:A)
endfunction

function! s:pluginList(A,L,P)
  if a:A =~ '/'
    return s:completion_filter(padrino#app().relglob('vendor/plugins/',matchstr(a:A,'.\{-\}/').'**/*'),a:A)
  else
    return s:completion_filter(padrino#app().relglob('vendor/plugins/',"*","/init.rb"),a:A)
  endif
endfunction

" Task files, not actual rake tasks
function! s:taskList(A,L,P)
  let all = padrino#app().relglob("lib/tasks/","**/*",".rake")
  if PadrinoFilePath() =~ '\<vendor/plugins/.'
    let path = s:sub(PadrinoFilePath(),'<vendor/plugins/[^/]*/\zs.*','')
    let all = padrino#app().relglob(path."tasks/","**/*",".rake")+padrino#app().relglob(path."lib/tasks/","**/*",".rake")+all
  endif
  return s:autocamelize(all,a:A)
endfunction

function! s:libList(A,L,P)
  let all = padrino#app().relglob('lib/',"**/*",".rb")
  if PadrinoFilePath() =~ '\<vendor/plugins/.'
    let path = s:sub(PadrinoFilePath(),'<vendor/plugins/[^/]*/\zs.*','lib/')
    let all = padrino#app().relglob(path,"**/*",".rb") + all
  endif
  return s:autocamelize(all,a:A)
endfunction

function! s:environmentList(A,L,P)
  return s:completion_filter(padrino#app().relglob("config/environments/","**/*",".rb"),a:A)
endfunction

function! s:initializerList(A,L,P)
  return s:completion_filter(padrino#app().relglob("config/initializers/","**/*",".rb"),a:A)
endfunction

function! s:Navcommand(bang,...)
  let suffix = ".rb"
  let filter = "**/*"
  let prefix = ""
  let default = ""
  let name = ""
  let i = 0
  while i < a:0
    let i += 1
    let arg = a:{i}
    if arg =~# '^-suffix='
      let suffix = matchstr(arg,'-suffix=\zs.*')
    elseif arg =~# '^-default='
      let default = matchstr(arg,'-default=\zs.*')
    elseif arg =~# '^-\%(glob\|filter\)='
      let filter = matchstr(arg,'-\w*=\zs.*')
    elseif arg !~# '^-'
      " A literal '\n'.  For evaluation below
      if name == ""
        let name = arg
      else
        let prefix .= "\\n".s:sub(arg,'/=$','/')
      endif
    endif
  endwhile
  let prefix = s:sub(prefix,'^\\n','')
  if name !~ '^[A-Za-z]\+$'
    return s:error("E182: Invalid command name")
  endif
  let cmds = 'ESVTD '
  let cmd = ''
  while cmds != ''
    exe 'command! -buffer -bar -bang -nargs=* -complete=customlist,'.s:sid.'CommandList R'.cmd.name." :call s:CommandEdit('".cmd."<bang>','".name."',\"".prefix."\",".string(suffix).",".string(filter).",".string(default).",<f-args>)"
    let cmd = strpart(cmds,0,1)
    let cmds = strpart(cmds,1)
  endwhile
endfunction

function! s:CommandList(A,L,P)
  let cmd = matchstr(a:L,'\CR[A-Z]\=\w\+')
  exe cmd." &"
  let lp = s:last_prefix . "\n"
  let res = []
  while lp != ""
    let p = matchstr(lp,'.\{-\}\ze\n')
    let lp = s:sub(lp,'.{-}\n','')
    let res += padrino#app().relglob(p,s:last_filter,s:last_suffix)
  endwhile
  if s:last_camelize
    return s:autocamelize(res,a:A)
  else
    return s:completion_filter(res,a:A)
  endif
endfunction

function! s:CommandEdit(cmd,name,prefix,suffix,filter,default,...)
  if a:0 && a:1 == "&"
    let s:last_prefix = a:prefix
    let s:last_suffix = a:suffix
    let s:last_filter = a:filter
    let s:last_camelize = (a:suffix =~# '\.rb$')
  else
    if a:default == "both()"
      if s:model() != ""
        let default = s:model()
      else
        let default = s:controller()
      endif
    elseif a:default == "model()"
      let default = s:model(1)
    elseif a:default == "controller()"
      let default = s:controller(1)
    else
      let default = a:default
    endif
    call s:EditSimpleRb(a:cmd,a:name,a:0 ? a:1 : default,a:prefix,a:suffix)
  endif
endfunction

function! s:EditSimpleRb(cmd,name,target,prefix,suffix,...)
  let cmd = s:findcmdfor(a:cmd)
  if a:target == ""
    " Good idea to emulate error numbers like this?
    return s:error("E471: Argument required")
  endif
  let f = a:0 ? a:target : padrino#underscore(a:target)
  let jump = matchstr(f,'[#!].*\|:\d*\%(:in\)\=$')
  let f = s:sub(f,'[#!].*|:\d*%(:in)=$','')
  if jump =~ '^!'
    let cmd = s:editcmdfor(cmd)
  endif
  if f == '.'
    let f = s:sub(f,'\.$','')
  else
    let f .= a:suffix.jump
  endif
  let f = s:gsub(a:prefix,'\n',f.'\n').f
  return s:findedit(cmd,f)
endfunction

function! s:app_migration(file) dict
  let arg = a:file
  if arg =~ '^0$\|^0\=[#:]'
    let suffix = s:sub(arg,'^0*','')
    if self.has_file('db/schema.rb')
      return 'db/schema.rb'.suffix
    elseif self.has_file('db/'.s:environment().'_structure.sql')
      return 'db/'.s:environment().'_structure.sql'.suffix
    else
      return 'db/schema.rb'.suffix
    endif
  elseif arg =~ '^\d$'
    let glob = '00'.arg.'_*.rb'
  elseif arg =~ '^\d\d$'
    let glob = '0'.arg.'_*.rb'
  elseif arg =~ '^\d\d\d$'
    let glob = ''.arg.'_*.rb'
  elseif arg == ''
    let glob = '*.rb'
  else
    let glob = '*'.padrino#underscore(arg).'*rb'
  endif
  let files = split(glob(self.path('db/migrate/').glob),"\n")
  call map(files,'strpart(v:val,1+strlen(self.path()))')
  let keep = get(files,0,'')
  if glob =~# '^\*.*\*rb'
    let pattern = glob[1:-4]
    call filter(files,'v:val =~# ''db/migrate/\d\+_''.pattern.''\.rb''')
    let keep = get(files,0,keep)
  endif
  return keep
endfunction

call s:add_methods('app', ['migration'])

function! s:migrationEdit(cmd,...)
  let cmd = s:findcmdfor(a:cmd)
  let arg = a:0 ? a:1 : ''
  let migr = arg == "." ? "db/migrate" : padrino#app().migration(arg)
  if migr != ''
    call s:findedit(cmd,migr)
  else
    return s:error("Migration not found".(arg=='' ? '' : ': '.arg))
  endif
endfunction

function! s:fixturesEdit(cmd,...)
  if a:0
    let c = padrino#underscore(a:1)
  else
    let c = padrino#pluralize(s:model(1))
  endif
  if c == ""
    return s:error("E471: Argument required")
  endif
  let e = fnamemodify(c,':e')
  let e = e == '' ? e : '.'.e
  let c = fnamemodify(c,':r')
  let file = get(padrino#app().test_suites(),0,'test').'/fixtures/'.c.e
  if file =~ '\.\w\+$' && padrino#app().find_file(c.e,["test/fixtures","spec/fixtures"]) ==# ''
    call s:edit(a:cmd,file)
  else
    call s:findedit(a:cmd,padrino#app().find_file(c.e,["test/fixtures","spec/fixtures"],[".yml",".csv"],file))
  endif
endfunction

function! s:localeEdit(cmd,...)
  let c = a:0 ? a:1 : padrino#app().default_locale()
  if c =~# '\.'
    call s:edit(a:cmd,padrino#app().find_file(c,'config/locales',[],'config/locales/'.c))
  else
    call s:findedit(a:cmd,padrino#app().find_file(c,'config/locales',['.yml','.rb'],'config/locales/'.c))
  endif
endfunction

function! s:metalEdit(cmd,...)
  if a:0
    call s:EditSimpleRb(a:cmd,"metal",a:1,"app/metal/",".rb")
  else
    call s:EditSimpleRb(a:cmd,"metal",'config/boot',"",".rb")
  endif
endfunction

function! s:modelEdit(cmd,...)
  call s:EditSimpleRb(a:cmd,"model",a:0? a:1 : s:model(1),"app/models/",".rb")
endfunction

function! s:observerEdit(cmd,...)
  call s:EditSimpleRb(a:cmd,"observer",a:0? a:1 : s:model(1),"app/models/","_observer.rb")
endfunction

function! s:viewEdit(cmd,...)
  if a:0 && a:1 =~ '^[^!#:]'
    let view = matchstr(a:1,'[^!#:]*')
  elseif padrino#buffer().type_name('controller','mailer')
    let view = s:lastmethod(line('.'))
  else
    let view = ''
  endif
  if view == ''
    return s:error("No view name given")
  elseif view == '.'
    return s:edit(a:cmd,'app/views')
  elseif view !~ '/' && s:controller(1) != ''
    let view = s:controller(1) . '/' . view
  endif
  if view !~ '/'
    return s:error("Cannot find view without controller")
  endif
  let file = "app/views/".view
  let found = s:findview(view)
  if found != ''
    let dir = fnamemodify(padrino#app().path(found),':h')
    if !isdirectory(dir)
      if a:0 && a:1 =~ '!'
        call mkdir(dir,'p')
      else
        return s:error('No such directory')
      endif
    endif
    call s:edit(a:cmd,found)
  elseif file =~ '\.\w\+$'
    call s:findedit(a:cmd,file)
  else
    let format = s:format(padrino#buffer().type_name('mailer') ? 'text' : 'html')
    if glob(padrino#app().path(file.'.'.format).'.*[^~]') != ''
      let file .= '.' . format
    endif
    call s:findedit(a:cmd,file)
  endif
endfunction

function! s:findview(name)
  let self = padrino#buffer()
  let name = a:name
  let pre = 'app/views/'
  if name !~# '/'
    let controller = self.controller_name(1)
    if controller != ''
      let name = controller.'/'.name
    endif
  endif
  if name =~# '\.\w\+\.\w\+$' || name =~# '\.'.s:viewspattern().'$'
    return pre.name
  else
    for format in ['.'.s:format('html'), '']
      for type in split(s:view_types,',')
        if self.app().has_file(pre.name.format.'.'.type)
          return pre.name.format.'.'.type
        endif
      endfor
    endfor
  endif
  return ''
endfunction

function! s:findlayout(name)
  return s:findview("layouts/".(a:name == '' ? 'application' : a:name))
endfunction

function! s:layoutEdit(cmd,...)
  if a:0
    return s:viewEdit(a:cmd,"layouts/".a:1)
  endif
  let file = s:findlayout(s:controller(1))
  if file == ""
    let file = s:findlayout("application")
  endif
  if file == ""
    let file = "app/views/layouts/application.html.erb"
  endif
  call s:edit(a:cmd,s:sub(file,'^/',''))
endfunction

function! s:controllerEdit(cmd,...)
  let suffix = '.rb'
  if a:0 == 0
    let controller = s:controller(1)
    if padrino#buffer().type_name() =~# '^view\%(-layout\|-partial\)\@!'
      let suffix .= '#'.expand('%:t:r')
    endif
  else
    let controller = a:1
  endif
  if padrino#app().has_file("app/controllers/".controller."_controller.rb") || !padrino#app().has_file("app/controllers/".controller.".rb")
    let suffix = "_controller".suffix
  endif
  return s:EditSimpleRb(a:cmd,"controller",controller,"app/controllers/",suffix)
endfunction

function! s:mailerEdit(cmd,...)
  return s:EditSimpleRb(a:cmd,"mailer",a:0? a:1 : s:controller(1),"app/mailers/\napp/models/",".rb")
endfunction

function! s:helperEdit(cmd,...)
  return s:EditSimpleRb(a:cmd,"helper",a:0? a:1 : s:controller(1),"app/helpers/","_helper.rb")
endfunction

function! s:stylesheetEdit(cmd,...)
  let name = a:0 ? a:1 : s:controller(1)
  if padrino#app().has('sass') && padrino#app().has_file('public/stylesheets/sass/'.name.'.sass')
    return s:EditSimpleRb(a:cmd,"stylesheet",name,"public/stylesheets/sass/",".sass",1)
  elseif padrino#app().has('sass') && padrino#app().has_file('public/stylesheets/sass/'.name.'.scss')
    return s:EditSimpleRb(a:cmd,"stylesheet",name,"public/stylesheets/sass/",".scss",1)
  elseif padrino#app().has('lesscss') && padrino#app().has_file('app/stylesheets/'.name.'.less')
    return s:EditSimpleRb(a:cmd,"stylesheet",name,"app/stylesheets/",".less",1)
  else
    return s:EditSimpleRb(a:cmd,"stylesheet",name,"public/stylesheets/",".css",1)
  endif
endfunction

function! s:javascriptEdit(cmd,...)
  let name = a:0 ? a:1 : s:controller(1)
  if padrino#app().has('coffee') && padrino#app().has_file('app/scripts/'.name.'.coffee')
    return s:EditSimpleRb(a:cmd,'javascript',name,'app/scripts/','.coffee',1)
  elseif padrino#app().has('coffee') && padrino#app().has_file('app/scripts/'.name.'.js')
    return s:EditSimpleRb(a:cmd,'javascript',name,'app/scripts/','.js',1)
  else
    return s:EditSimpleRb(a:cmd,'javascript',name,'public/javascripts/','.js',1)
  endif
endfunction

function! s:unittestEdit(cmd,...)
  let f = padrino#underscore(a:0 ? matchstr(a:1,'[^!#:]*') : s:model(1))
  let jump = a:0 ? matchstr(a:1,'[!#:].*') : ''
  if jump =~ '!'
    let cmd = s:editcmdfor(a:cmd)
  else
    let cmd = s:findcmdfor(a:cmd)
  endif
  let mapping = {'test': ['test/unit/','_test.rb'], 'spec': ['spec/models/','_spec.rb']}
  let tests = map(filter(padrino#app().test_suites(),'has_key(mapping,v:val)'),'get(mapping,v:val)')
  if empty(tests)
    let tests = [mapping['test']]
  endif
  for [prefix, suffix] in tests
    if !a:0 && padrino#buffer().type_name('model-aro') && f != '' && f !~# '_observer$'
      if padrino#app().has_file(prefix.f.'_observer'.suffix)
        return s:findedit(cmd,prefix.f.'_observer'.suffix.jump)
      endif
    endif
  endfor
  for [prefix, suffix] in tests
    if padrino#app().has_file(prefix.f.suffix)
      return s:findedit(cmd,prefix.f.suffix.jump)
    endif
  endfor
  return s:EditSimpleRb(a:cmd,"unittest",f.jump,tests[0][0],tests[0][1],1)
endfunction

function! s:functionaltestEdit(cmd,...)
  let f = padrino#underscore(a:0 ? matchstr(a:1,'[^!#:]*') : s:controller(1))
  let jump = a:0 ? matchstr(a:1,'[!#:].*') : ''
  if jump =~ '!'
    let cmd = s:editcmdfor(a:cmd)
  else
    let cmd = s:findcmdfor(a:cmd)
  endif
  let mapping = {'test': [['test/functional/'],['_test.rb','_controller_test.rb']], 'spec': [['spec/controllers/','spec/mailers/'],['_spec.rb','_controller_spec.rb']]}
  let tests = map(filter(padrino#app().test_suites(),'has_key(mapping,v:val)'),'get(mapping,v:val)')
  if empty(tests)
    let tests = [mapping[tests]]
  endif
  for [prefixes, suffixes] in tests
    for prefix in prefixes
      for suffix in suffixes
        if padrino#app().has_file(prefix.f.suffix)
          return s:findedit(cmd,prefix.f.suffix.jump)
        endif
      endfor
    endfor
  endfor
  return s:EditSimpleRb(a:cmd,"functionaltest",f.jump,tests[0][0][0],tests[0][1][0],1)
endfunction

function! s:integrationtestEdit(cmd,...)
  if !a:0
    return s:EditSimpleRb(a:cmd,"integrationtest","test/test_helper\nfeatures/support/env\nspec/spec_helper","",".rb")
  endif
  let f = padrino#underscore(matchstr(a:1,'[^!#:]*'))
  let jump = matchstr(a:1,'[!#:].*')
  if jump =~ '!'
    let cmd = s:editcmdfor(a:cmd)
  else
    let cmd = s:findcmdfor(a:cmd)
  endif
  let tests = [['test/integration/','_test.rb'], [ 'spec/requests/','_spec.rb'], [ 'spec/integration/','_spec.rb'], [ 'features/','.feature']]
  call filter(tests, 'isdirectory(padrino#app().path(v:val[0]))')
  if empty(tests)
    let tests = [['test/integration/','_test.rb']]
  endif
  for [prefix, suffix] in tests
    if padrino#app().has_file(prefix.f.suffix)
      return s:findedit(cmd,prefix.f.suffix.jump)
    elseif padrino#app().has_file(prefix.padrino#underscore(f).suffix)
      return s:findedit(cmd,prefix.padrino#underscore(f).suffix.jump)
    endif
  endfor
  return s:EditSimpleRb(a:cmd,"integrationtest",f.jump,tests[0][0],tests[0][1],1)
endfunction

function! s:specEdit(cmd,...)
  if a:0
    return s:EditSimpleRb(a:cmd,"spec",a:1,"spec/","_spec.rb")
  else
    call s:EditSimpleRb(a:cmd,"spec","spec_helper","spec/",".rb")
  endif
endfunction

function! s:pluginEdit(cmd,...)
  let cmd = s:findcmdfor(a:cmd)
  let plugin = ""
  let extra = ""
  if PadrinoFilePath() =~ '\<vendor/plugins/.'
    let plugin = matchstr(PadrinoFilePath(),'\<vendor/plugins/\zs[^/]*\ze')
    let extra = "vendor/plugins/" . plugin . "/\n"
  endif
  if a:0
    if a:1 =~ '^[^/.]*/\=$' && padrino#app().has_file("vendor/plugins/".a:1."/init.rb")
      return s:EditSimpleRb(a:cmd,"plugin",s:sub(a:1,'/$',''),"vendor/plugins/","/init.rb")
    elseif plugin == ""
      call s:edit(cmd,"vendor/plugins/".s:sub(a:1,'\.$',''))
    elseif a:1 == "."
      call s:findedit(cmd,"vendor/plugins/".plugin)
    elseif isdirectory(padrino#app().path("vendor/plugins/".matchstr(a:1,'^[^/]*')))
      call s:edit(cmd,"vendor/plugins/".a:1)
    else
      call s:findedit(cmd,"vendor/plugins/".a:1."\nvendor/plugins/".plugin."/".a:1)
    endif
  else
    call s:findedit(a:cmd,"Gemfile")
  endif
endfunction

function! s:taskEdit(cmd,...)
  let plugin = ""
  let extra = ""
  if PadrinoFilePath() =~ '\<vendor/plugins/.'
    let plugin = matchstr(PadrinoFilePath(),'\<vendor/plugins/[^/]*')
    let extra = plugin."/tasks/\n".plugin."/lib/tasks/\n"
  endif
  if a:0
    call s:EditSimpleRb(a:cmd,"task",a:1,extra."lib/tasks/",".rake")
  else
    call s:findedit(a:cmd,(plugin != "" ? plugin."/Rakefile\n" : "")."Rakefile")
  endif
endfunction

function! s:libEdit(cmd,...)
  let extra = ""
  if PadrinoFilePath() =~ '\<vendor/plugins/.'
    let extra = s:sub(PadrinoFilePath(),'<vendor/plugins/[^/]*/\zs.*','lib/')."\n"
  endif
  if a:0
    call s:EditSimpleRb(a:cmd,"lib",a:0? a:1 : "",extra."lib/",".rb")
  else
    call s:EditSimpleRb(a:cmd,"lib","seeds","db/",".rb")
  endif
endfunction

function! s:environmentEdit(cmd,...)
  if a:0 || padrino#app().has_file('config/application.rb')
    return s:EditSimpleRb(a:cmd,"environment",a:0? a:1 : "../application","config/environments/",".rb")
  else
    return s:EditSimpleRb(a:cmd,"environment","environment","config/",".rb")
  endif
endfunction

function! s:initializerEdit(cmd,...)
  return s:EditSimpleRb(a:cmd,"initializer",a:0? a:1 : "../routes","config/initializers/",".rb")
endfunction

" }}}1
" Alternate/Related {{{1

function! s:findcmdfor(cmd)
  let bang = ''
  if a:cmd =~ '\!$'
    let bang = '!'
    let cmd = s:sub(a:cmd,'\!$','')
  else
    let cmd = a:cmd
  endif
  if cmd =~ '^\d'
    let num = matchstr(cmd,'^\d\+')
    let cmd = s:sub(cmd,'^\d+','')
  else
    let num = ''
  endif
  if cmd == '' || cmd == 'E' || cmd == 'F'
    return num.'find'.bang
  elseif cmd == 'S'
    return num.'sfind'.bang
  elseif cmd == 'V'
    return 'vert '.num.'sfind'.bang
  elseif cmd == 'T'
    return num.'tabfind'.bang
  elseif cmd == 'D'
    return num.'read'.bang
  else
    return num.cmd.bang
  endif
endfunction

function! s:editcmdfor(cmd)
  let cmd = s:findcmdfor(a:cmd)
  let cmd = s:sub(cmd,'<sfind>','split')
  let cmd = s:sub(cmd,'find>','edit')
  return cmd
endfunction

function! s:try(cmd) abort
  if !exists(":try")
    " I've seen at least one weird setup without :try
    exe a:cmd
  else
    try
      exe a:cmd
    catch
      call s:error(s:sub(v:exception,'^.{-}:\zeE',''))
      return 0
    endtry
  endif
  return 1
endfunction

function! s:findedit(cmd,files,...) abort
  let cmd = s:findcmdfor(a:cmd)
  let files = type(a:files) == type([]) ? copy(a:files) : split(a:files,"\n")
  if len(files) == 1
    let file = files[0]
  else
    let file = get(filter(copy(files),'padrino#app().has_file(s:sub(v:val,"#.*|:\\d*$",""))'),0,get(files,0,''))
  endif
  if file =~ '[#!]\|:\d*\%(:in\)\=$'
    let djump = matchstr(file,'!.*\|#\zs.*\|:\zs\d*\ze\%(:in\)\=$')
    let file = s:sub(file,'[#!].*|:\d*%(:in)=$','')
  else
    let djump = ''
  endif
  if file == ''
    let testcmd = "edit"
  elseif isdirectory(padrino#app().path(file))
    let arg = file == "." ? padrino#app().path() : padrino#app().path(file)
    let testcmd = s:editcmdfor(cmd).' '.(a:0 ? a:1 . ' ' : '').s:escarg(arg)
    exe testcmd
    return
  elseif padrino#app().path() =~ '://' || cmd =~ 'edit' || cmd =~ 'split'
    if file !~ '^/' && file !~ '^\w:' && file !~ '://'
      let file = s:escarg(padrino#app().path(file))
    endif
    let testcmd = s:editcmdfor(cmd).' '.(a:0 ? a:1 . ' ' : '').file
  else
    let testcmd = cmd.' '.(a:0 ? a:1 . ' ' : '').file
  endif
  if s:try(testcmd)
    call s:djump(djump)
  endif
endfunction

function! s:edit(cmd,file,...)
  let cmd = s:editcmdfor(a:cmd)
  let cmd .= ' '.(a:0 ? a:1 . ' ' : '')
  let file = a:file
  if file !~ '^/' && file !~ '^\w:' && file !~ '://'
    exe cmd."`=fnamemodify(padrino#app().path(file),':.')`"
  else
    exe cmd.file
  endif
endfunction

function! s:Alternate(cmd,line1,line2,count,...)
  if a:0
    if a:count && a:cmd !~# 'D'
      return call('s:Find',[1,a:line1.a:cmd]+a:000)
    elseif a:count
      return call('s:Edit',[1,a:line1.a:cmd]+a:000)
    else
      return call('s:Edit',[1,a:cmd]+a:000)
    endif
  else
    let file = s:getopt(a:count ? 'related' : 'alternate', 'bl')
    if file == ''
      let file = padrino#buffer().related(a:count)
    endif
    if file != ''
      call s:findedit(a:cmd,file)
    else
      call s:warn("No alternate file is defined")
    endif
  endif
endfunction

function! s:Related(cmd,line1,line2,count,...)
  if a:count == 0 && a:0 == 0
    return s:Alternate(a:cmd,a:line1,a:line1,a:line1)
  else
    return call('s:Alternate',[a:cmd,a:line1,a:line2,a:count]+a:000)
  endif
endfunction

function! s:Complete_related(A,L,P)
  if a:L =~# '^[[:alpha:]]'
    return s:Complete_edit(a:A,a:L,a:P)
  else
    return s:Complete_find(a:A,a:L,a:P)
  endif
endfunction

function! s:readable_related(...) dict abort
  let f = self.name()
  if a:0 && a:1
    let lastmethod = self.last_method(a:1)
    if self.type_name('controller','mailer') && lastmethod != ""
      let root = s:sub(s:sub(s:sub(f,'/application%(_controller)=\.rb$','/shared_controller.rb'),'/%(controllers|models|mailers)/','/views/'),'%(_controller)=\.rb$','/'.lastmethod)
      let format = self.last_format(a:1)
      if format == ''
        let format = self.type_name('mailer') ? 'text' : 'html'
      endif
      if glob(self.app().path().'/'.root.'.'.format.'.*[^~]') != ''
        return root . '.' . format
      else
        return root
      endif
    elseif f =~ '\<config/environments/'
      return "config/database.yml#". fnamemodify(f,':t:r')
    elseif f =~ '\<config/database\.yml$'
      if lastmethod != ""
        return "config/environments/".lastmethod.".rb"
      else
        return "config/application.rb\nconfig/environment.rb"
      endif
    elseif f =~ '\<config/routes\.rb$'      | return "config/database.yml"
    elseif f =~ '\<config/\%(application\|environment\)\.rb$'
      return "config/routes.rb"
    elseif self.type_name('view-layout')
      return s:sub(s:sub(f,'/views/','/controllers/'),'/layouts/(\k+)\..*$','/\1_controller.rb')
    elseif self.type_name('view')
      let controller  = s:sub(s:sub(f,'/views/','/controllers/'),'/(\k+%(\.\k+)=)\..*$','_controller.rb#\1')
      let controller2 = s:sub(s:sub(f,'/views/','/controllers/'),'/(\k+%(\.\k+)=)\..*$','.rb#\1')
      let mailer      = s:sub(s:sub(f,'/views/','/mailers/'),'/(\k+%(\.\k+)=)\..*$','.rb#\1')
      let model       = s:sub(s:sub(f,'/views/','/models/'),'/(\k+)\..*$','.rb#\1')
      if self.app().has_file(s:sub(controller,'#.{-}$',''))
        return controller
      elseif self.app().has_file(s:sub(controller2,'#.{-}$',''))
        return controller2
      elseif self.app().has_file(s:sub(mailer,'#.{-}$',''))
        return mailer
      elseif self.app().has_file(s:sub(model,'#.{-}$','')) || model =~ '_mailer\.rb#'
        return model
      else
        return controller
      endif
    elseif self.type_name('controller')
      return s:sub(s:sub(f,'/controllers/','/helpers/'),'%(_controller)=\.rb$','_helper.rb')
    " elseif self.type_name('helper')
      " return s:findlayout(s:controller())
    elseif self.type_name('model-arb')
      let table_name = matchstr(join(self.getline(1,50),"\n"),'\n\s*set_table_name\s*[:"'']\zs\w\+')
      if table_name == ''
        let table_name = padrino#pluralize(s:gsub(s:sub(fnamemodify(f,':r'),'.{-}<app/models/',''),'/','_'))
      endif
      return self.app().migration('0#'.table_name)
    elseif self.type_name('model-aro')
      return s:sub(f,'_observer\.rb$','.rb')
    elseif self.type_name('db-schema')
      return self.app().migration(1)
    endif
  endif
  if f =~ '\<config/environments/'
    return "config/application.rb\nconfig/environment.rb"
  elseif f == 'README'
    return "config/database.yml"
  elseif f =~ '\<config/database\.yml$'   | return "config/routes.rb"
  elseif f =~ '\<config/routes\.rb$'
    return "config/application.rb\nconfig/environment.rb"
  elseif f =~ '\<config/\%(application\|environment\)\.rb$'
    return "config/database.yml"
  elseif f =~ '\<db/migrate/'
    let migrations = sort(self.app().relglob('db/migrate/','*','.rb'))
    let me = matchstr(f,'\<db/migrate/\zs.*\ze\.rb$')
    if !exists('l:lastmethod') || lastmethod == 'down'
      let candidates = reverse(filter(copy(migrations),'v:val < me'))
      let migration = "db/migrate/".get(candidates,0,migrations[-1]).".rb"
    else
      let candidates = filter(copy(migrations),'v:val > me')
      let migration = "db/migrate/".get(candidates,0,migrations[0]).".rb"
    endif
    return migration . (exists('l:lastmethod') && lastmethod != '' ? '#'.lastmethod : '')
  elseif f =~ '\<application\.js$'
    return "app/helpers/application_helper.rb"
  elseif self.type_name('javascript')
    return "public/javascripts/application.js"
  elseif self.type_name('db/schema')
    return self.app().migration('')
  elseif self.type_name('view')
    let spec1 = fnamemodify(f,':s?\<app/?spec/?')."_spec.rb"
    let spec2 = fnamemodify(f,':r:s?\<app/?spec/?')."_spec.rb"
    let spec3 = fnamemodify(f,':r:r:s?\<app/?spec/?')."_spec.rb"
    if self.app().has_file(spec1)
      return spec1
    elseif self.app().has_file(spec2)
      return spec2
    elseif self.app().has_file(spec3)
      return spec3
    elseif self.app().has('spec')
      return spec2
    else
      if self.type_name('view-layout')
        let dest = fnamemodify(f,':r:s?/layouts\>??').'/layout.'.fnamemodify(f,':e')
      else
        let dest = f
      endif
      return s:sub(s:sub(dest,'<app/views/','test/functional/'),'/[^/]*$','_controller_test.rb')
    endif
  elseif self.type_name('controller-api')
    let api = s:sub(s:sub(f,'/controllers/','/apis/'),'_controller\.rb$','_api.rb')
    return api
  elseif self.type_name('api')
    return s:sub(s:sub(f,'/apis/','/controllers/'),'_api\.rb$','_controller.rb')
  elseif self.type_name('fixtures') && f =~ '\<spec/'
    let file = padrino#singularize(fnamemodify(f,":t:r")).'_spec.rb'
    return file
  elseif self.type_name('fixtures')
    let file = padrino#singularize(fnamemodify(f,":t:r")).'_test.rb'
    return file
  elseif f == ''
    call s:warn("No filename present")
  elseif f =~ '\<test/unit/routing_test\.rb$'
    return 'config/routes.rb'
  elseif self.type_name('spec-view')
    return s:sub(s:sub(f,'<spec/','app/'),'_spec\.rb$','')
  elseif fnamemodify(f,":e") == "rb"
    let file = fnamemodify(f,":r")
    if file =~ '_\%(test\|spec\)$'
      let file = s:sub(file,'_%(test|spec)$','.rb')
    else
      let file .= '_test.rb'
    endif
    if self.type_name('helper')
      return s:sub(file,'<app/helpers/','test/unit/helpers/')."\n".s:sub(s:sub(file,'_test\.rb$','_spec.rb'),'<app/helpers/','spec/helpers/')
    elseif self.type_name('model')
      return s:sub(file,'<app/models/','test/unit/')."\n".s:sub(s:sub(file,'_test\.rb$','_spec.rb'),'<app/models/','spec/models/')
    elseif self.type_name('controller')
      return s:sub(file,'<app/controllers/','test/functional/')."\n".s:sub(s:sub(file,'_test\.rb$','_spec.rb'),'app/controllers/','spec/controllers/')
    elseif self.type_name('mailer')
      return s:sub(file,'<app/m%(ailer|odel)s/','test/unit/')."\n".s:sub(s:sub(file,'_test\.rb$','_spec.rb'),'<app/','spec/')
    elseif self.type_name('test-unit')
      return s:sub(s:sub(file,'test/unit/helpers/','app/helpers/'),'test/unit/','app/models/')."\n".s:sub(file,'test/unit/','lib/')
    elseif self.type_name('test-functional')
      if file =~ '_api\.rb'
        return s:sub(file,'test/functional/','app/apis/')
      elseif file =~ '_controller\.rb'
        return s:sub(file,'test/functional/','app/controllers/')
      else
        return s:sub(file,'test/functional/','')
      endif
    elseif self.type_name('spec-lib')
      return s:sub(file,'<spec/','')
    elseif self.type_name('lib')
      return s:sub(f, '<lib/(.*)\.rb$', 'test/unit/\1_test.rb')."\n".s:sub(f, '<lib/(.*)\.rb$', 'spec/lib/\1_spec.rb')
    elseif self.type_name('spec')
      return s:sub(file,'<spec/','app/')
    elseif file =~ '\<vendor/.*/lib/'
      return s:sub(file,'<vendor/.{-}/\zslib/','test/')
    elseif file =~ '\<vendor/.*/test/'
      return s:sub(file,'<vendor/.{-}/\zstest/','lib/')
    else
      return fnamemodify(file,':t')."\n".s:sub(s:sub(f,'\.rb$','_spec.rb'),'^app/','spec/')
    endif
  else
    return ""
  endif
endfunction

call s:add_methods('readable',['related'])

" }}}1
" Partial Extraction {{{1

function! s:Extract(bang,...) range abort
  if a:0 == 0 || a:0 > 1
    return s:error("Incorrect number of arguments")
  endif
  if a:1 =~ '[^a-z0-9_/.]'
    return s:error("Invalid partial name")
  endif
  let padrino_root = padrino#app().path()
  let ext = expand("%:e")
  let file = s:sub(a:1,'%(/|^)\zs_\ze[^/]*$','')
  let first = a:firstline
  let last = a:lastline
  let range = first.",".last
  if padrino#buffer().type_name('view-layout')
    if PadrinoFilePath() =~ '\<app/views/layouts/application\>'
      let curdir = 'app/views/shared'
      if file !~ '/'
        let file = "shared/" .file
      endif
    else
      let curdir = s:sub(PadrinoFilePath(),'.*<app/views/layouts/(.*)%(\.\w*)$','app/views/\1')
    endif
  else
    let curdir = fnamemodify(PadrinoFilePath(),':h')
  endif
  let curdir = padrino_root."/".curdir
  let dir = fnamemodify(file,":h")
  let fname = fnamemodify(file,":t")
  if fnamemodify(fname,":e") == ""
    let name = fname
    let fname .= ".".matchstr(expand("%:t"),'\.\zs.*')
  elseif fnamemodify(fname,":e") !~ '^'.s:viewspattern().'$'
    let name = fnamemodify(fname,":r")
    let fname .= ".".ext
  else
    let name = fnamemodify(fname,":r:r")
  endif
  let var = "@".name
  let collection = ""
  if dir =~ '^/'
    let out = (padrino_root).dir."/_".fname
  elseif dir == "" || dir == "."
    let out = (curdir)."/_".fname
  elseif isdirectory(curdir."/".dir)
    let out = (curdir)."/".dir."/_".fname
  else
    let out = (padrino_root)."/app/views/".dir."/_".fname
  endif
  if filereadable(out) && !a:bang
    return s:error('E13: File exists (add ! to override)')
  endif
  if !isdirectory(fnamemodify(out,':h'))
    if a:bang
      call mkdir(fnamemodify(out,':h'),'p')
    else
      return s:error('No such directory')
    endif
  endif
  " No tabs, they'll just complicate things
  if ext =~? '^\%(rhtml\|erb\|dryml\)$'
    let erub1 = '\<\%\s*'
    let erub2 = '\s*-=\%\>'
  else
    let erub1 = ''
    let erub2 = ''
  endif
  let spaces = matchstr(getline(first),"^ *")
  if getline(last+1) =~ '\v^\s*'.erub1.'end'.erub2.'\s*$'
    let fspaces = matchstr(getline(last+1),"^ *")
    if getline(first-1) =~ '\v^'.fspaces.erub1.'for\s+(\k+)\s+in\s+([^ %>]+)'.erub2.'\s*$'
      let collection = s:sub(getline(first-1),'^'.fspaces.erub1.'for\s+(\k+)\s+in\s+([^ >]+)'.erub2.'\s*$','\1>\2')
    elseif getline(first-1) =~ '\v^'.fspaces.erub1.'([^ %>]+)\.each\s+do\s+\|\s*(\k+)\s*\|'.erub2.'\s*$'
      let collection = s:sub(getline(first-1),'^'.fspaces.erub1.'([^ %>]+)\.each\s+do\s+\|\s*(\k+)\s*\|'.erub2.'\s*$','\2>\1')
    endif
    if collection != ''
      let var = matchstr(collection,'^\k\+')
      let collection = s:sub(collection,'^\k+\>','')
      let first -= 1
      let last += 1
    endif
  else
    let fspaces = spaces
  endif
  let renderstr = "render :partial => '".fnamemodify(file,":r:r")."'"
  if collection != ""
    let renderstr .= ", :collection => ".collection
  elseif "@".name != var
    let renderstr .= ", :object => ".var
  endif
  if ext =~? '^\%(rhtml\|erb\|dryml\)$'
    let renderstr = "<%= ".renderstr." %>"
  elseif ext == "rxml" || ext == "builder"
    let renderstr = "xml << ".s:sub(renderstr,"render ","render(").")"
  elseif ext == "rjs"
    let renderstr = "page << ".s:sub(renderstr,"render ","render(").")"
  elseif ext == "haml"
    let renderstr = "= ".renderstr
  elseif ext == "mn"
    let renderstr = "_".renderstr
  endif
  let buf = @@
  silent exe range."yank"
  let partial = @@
  let @@ = buf
  let old_ai = &ai
  try
    let &ai = 0
    silent exe "norm! :".first.",".last."change\<CR>".fspaces.renderstr."\<CR>.\<CR>"
  finally
    let &ai = old_ai
  endtry
  if renderstr =~ '<%'
    norm ^6w
  else
    norm ^5w
  endif
  let ft = &ft
  let shortout = fnamemodify(out,':.')
  silent split `=shortout`
  silent %delete
  let &ft = ft
  let @@ = partial
  silent put
  0delete
  let @@ = buf
  if spaces != ""
    silent! exe '%substitute/^'.spaces.'//'
  endif
  silent! exe '%substitute?\%(\w\|[@:"'."'".'-]\)\@<!'.var.'\>?'.name.'?g'
  1
endfunction

" }}}1
" Migration Inversion {{{1

function! s:mkeep(str)
  " Things to keep (like comments) from a migration statement
  return matchstr(a:str,' #[^{].*')
endfunction

function! s:mextargs(str,num)
  if a:str =~ '^\s*\w\+\s*('
    return s:sub(matchstr(a:str,'^\s*\w\+\s*\zs(\%([^,)]\+[,)]\)\{,'.a:num.'\}'),',$',')')
  else
    return s:sub(s:sub(matchstr(a:str,'\w\+\>\zs\s*\%([^,){ ]*[, ]*\)\{,'.a:num.'\}'),'[, ]*$',''),'^\s+',' ')
  endif
endfunction

function! s:migspc(line)
  return matchstr(a:line,'^\s*')
endfunction

function! s:invertrange(beg,end)
  let str = ""
  let lnum = a:beg
  while lnum <= a:end
    let line = getline(lnum)
    let add = ""
    if line == ''
      let add = ' '
    elseif line =~ '^\s*\(#[^{].*\)\=$'
      let add = line
    elseif line =~ '\<create_table\>'
      let add = s:migspc(line)."drop_table".s:mextargs(line,1).s:mkeep(line)
      let lnum = s:endof(lnum)
    elseif line =~ '\<drop_table\>'
      let add = s:sub(line,'<drop_table>\s*\(=\s*([^,){ ]*).*','create_table \1 do |t|'."\n".matchstr(line,'^\s*').'end').s:mkeep(line)
    elseif line =~ '\<add_column\>'
      let add = s:migspc(line).'remove_column'.s:mextargs(line,2).s:mkeep(line)
    elseif line =~ '\<remove_column\>'
      let add = s:sub(line,'<remove_column>','add_column')
    elseif line =~ '\<add_index\>'
      let add = s:migspc(line).'remove_index'.s:mextargs(line,1)
      let mat = matchstr(line,':name\s*=>\s*\zs[^ ,)]*')
      if mat != ''
        let add = s:sub(add,'\)=$',', :name => '.mat.'&')
      else
        let mat = matchstr(line,'\<add_index\>[^,]*,\s*\zs\%(\[[^]]*\]\|[:"'."'".']\w*["'."'".']\=\)')
        if mat != ''
          let add = s:sub(add,'\)=$',', :column => '.mat.'&')
        endif
      endif
      let add .= s:mkeep(line)
    elseif line =~ '\<remove_index\>'
      let add = s:sub(s:sub(line,'<remove_index','add_index'),':column\s*=>\s*','')
    elseif line =~ '\<rename_\%(table\|column\)\>'
      let add = s:sub(line,'<rename_%(table\s*\(=\s*|column\s*\(=\s*[^,]*,\s*)\zs([^,]*)(,\s*)([^,]*)','\3\2\1')
    elseif line =~ '\<change_column\>'
      let add = s:migspc(line).'change_column'.s:mextargs(line,2).s:mkeep(line)
    elseif line =~ '\<change_column_default\>'
      let add = s:migspc(line).'change_column_default'.s:mextargs(line,2).s:mkeep(line)
    elseif line =~ '\.update_all(\(["'."'".']\).*\1)$' || line =~ '\.update_all \(["'."'".']\).*\1$'
      " .update_all('a = b') => .update_all('b = a')
      let pre = matchstr(line,'^.*\.update_all[( ][}'."'".'"]')
      let post = matchstr(line,'["'."'".'])\=$')
      let mat = strpart(line,strlen(pre),strlen(line)-strlen(pre)-strlen(post))
      let mat = s:gsub(','.mat.',','%(,\s*)@<=([^ ,=]{-})(\s*\=\s*)([^,=]{-})%(\s*,)@=','\3\2\1')
      let add = pre.s:sub(s:sub(mat,'^,',''),',$','').post
    elseif line =~ '^s\*\%(if\|unless\|while\|until\|for\)\>'
      let lnum = s:endof(lnum)
    endif
    if lnum == 0
      return -1
    endif
    if add == ""
      let add = s:sub(line,'^\s*\zs.*','raise ActiveRecord::IrreversibleMigration')
    elseif add == " "
      let add = ""
    endif
    let str = add."\n".str
    let lnum += 1
  endwhile
  let str = s:gsub(str,'(\s*raise ActiveRecord::IrreversibleMigration\n)+','\1')
  return str
endfunction

function! s:Invert(bang)
  let err = "Could not parse method"
  let src = "up"
  let dst = "down"
  let beg = search('\%('.&l:define.'\).*'.src.'\>',"w")
  let end = s:endof(beg)
  if beg + 1 == end
    let src = "down"
    let dst = "up"
    let beg = search('\%('.&l:define.'\).*'.src.'\>',"w")
    let end = s:endof(beg)
  endif
  if !beg || !end
    return s:error(err)
  endif
  let str = s:invertrange(beg+1,end-1)
  if str == -1
    return s:error(err)
  endif
  let beg = search('\%('.&l:define.'\).*'.dst.'\>',"w")
  let end = s:endof(beg)
  if !beg || !end
    return s:error(err)
  endif
  if foldclosed(beg) > 0
    exe beg."foldopen!"
  endif
  if beg + 1 < end
    exe (beg+1).",".(end-1)."delete _"
  endif
  if str != ''
    exe beg.'put =str'
    exe 1+beg
  endif
endfunction

" }}}1
" Cache {{{1

let s:cache_prototype = {'dict': {}}

function! s:cache_clear(...) dict
  if a:0 == 0
    let self.dict = {}
  elseif has_key(self,'dict') && has_key(self.dict,a:1)
    unlet! self.dict[a:1]
  endif
endfunction

function! padrino#cache_clear(...)
  if exists('b:padrino_root')
    return call(padrino#app().cache.clear,a:000,padrino#app().cache)
  endif
endfunction

function! s:cache_get(...) dict
  if a:0 == 1
    return self.dict[a:1]
  else
    return self.dict
  endif
endfunction

function! s:cache_has(key) dict
  return has_key(self.dict,a:key)
endfunction

function! s:cache_needs(key) dict
  return !has_key(self.dict,a:key)
endfunction

function! s:cache_set(key,value) dict
  let self.dict[a:key] = a:value
endfunction

call s:add_methods('cache', ['clear','needs','has','get','set'])

let s:app_prototype.cache = s:cache_prototype

" }}}1
" Syntax {{{1

function! s:resetomnicomplete()
  if exists("+completefunc") && &completefunc == 'syntaxcomplete#Complete'
    if exists("g:loaded_syntax_completion")
      " Ugly but necessary, until we have our own completion
      unlet g:loaded_syntax_completion
      silent! delfunction syntaxcomplete#Complete
    endif
  endif
endfunction

function! s:helpermethods()
  return ""
        \."atom_feed audio_path audio_tag auto_discovery_link_tag auto_link "
        \."button_to button_to_function "
        \."cache capture cdata_section check_box check_box_tag collection_select concat content_for content_tag content_tag_for csrf_meta_tag current_cycle cycle "
        \."date_select datetime_select debug distance_of_time_in_words distance_of_time_in_words_to_now div_for dom_class dom_id draggable_element draggable_element_js drop_receiving_element drop_receiving_element_js "
        \."email_field email_field_tag error_message_on error_messages_for escape_javascript escape_once excerpt "
        \."favicon_link_tag field_set_tag fields_for file_field file_field_tag form form_for form_tag "
        \."grouped_collection_select grouped_options_for_select "
        \."hidden_field hidden_field_tag highlight "
        \."image_path image_submit_tag image_tag input "
        \."javascript_cdata_section javascript_include_tag javascript_path javascript_tag "
        \."l label label_tag link_to link_to_function link_to_if link_to_unless link_to_unless_current localize "
        \."mail_to "
        \."number_field number_field_tag number_to_currency number_to_human number_to_human_size number_to_percentage number_to_phone number_with_delimiter number_with_precision "
        \."option_groups_from_collection_for_select options_for_select options_from_collection_for_select "
        \."password_field password_field_tag path_to_audio path_to_image path_to_javascript path_to_stylesheet path_to_video phone_field phone_field_tag pluralize "
        \."radio_button radio_button_tag range_field range_field_tag raw remote_function reset_cycle "
        \."safe_concat sanitize sanitize_css search_field search_field_tag select select_date select_datetime select_day select_hour select_minute select_month select_second select_tag select_time select_year simple_format sortable_element sortable_element_js strip_links strip_tags stylesheet_link_tag stylesheet_path submit_tag button_tag "
        \."t tag telephone_field telephone_field_tag text_area text_area_tag text_field text_field_tag time_ago_in_words time_select time_zone_options_for_select time_zone_select translate truncate "
        \."update_page update_page_tag url_field url_field_tag url_for url_options "
        \."video_path video_tag visual_effect "
        \."word_wrap"
endfunction

function! s:app_user_classes() dict
  if self.cache.needs("user_classes")
    let controllers = self.relglob("app/controllers/","**/*",".rb")
    call map(controllers,'v:val == "application" ? v:val."_controller" : v:val')
    let classes =
          \ self.relglob("app/models/","**/*",".rb") +
          \ controllers +
          \ self.relglob("app/helpers/","**/*",".rb") +
          \ self.relglob("lib/","**/*",".rb")
    call map(classes,'padrino#camelize(v:val)')
    call self.cache.set("user_classes",classes)
  endif
  return self.cache.get('user_classes')
endfunction

function! s:app_user_assertions() dict
  if self.cache.needs("user_assertions")
    if self.has_file("test/test_helper.rb")
      let assertions = map(filter(s:readfile(self.path("test/test_helper.rb")),'v:val =~ "^  def assert_"'),'matchstr(v:val,"^  def \\zsassert_\\w\\+")')
    else
      let assertions = []
    endif
    call self.cache.set("user_assertions",assertions)
  endif
  return self.cache.get('user_assertions')
endfunction

call s:add_methods('app', ['user_classes','user_assertions'])

function! s:BufSyntax()
  if (!exists("g:padrino_syntax") || g:padrino_syntax)
    let buffer = padrino#buffer()
    let s:javascript_functions = "$ $$ $A $F $H $R $w jQuery"
    let classes = s:gsub(join(padrino#app().user_classes(),' '),'::',' ')
    if &syntax == 'ruby'
      if classes != ''
        exe "syn keyword rubyPadrinoUserClass ".classes." containedin=rubyClassDeclaration,rubyModuleDeclaration,rubyClass,rubyModule"
      endif
      if buffer.type_name() == ''
        syn keyword rubyPadrinoMethod params request response session headers cookies flash
      endif
      if buffer.type_name('api')
        syn keyword rubyPadrinoAPIMethod api_method inflect_names
      endif
      if buffer.type_name() ==# 'model' || buffer.type_name('model-arb')
        syn keyword rubyPadrinoARMethod default_scope named_scope scope serialize
        syn keyword rubyPadrinoARAssociationMethod belongs_to has_one has_many has_and_belongs_to_many composed_of accepts_nested_attributes_for
        syn keyword rubyPadrinoARCallbackMethod before_create before_destroy before_save before_update before_validation before_validation_on_create before_validation_on_update
        syn keyword rubyPadrinoARCallbackMethod after_create after_destroy after_save after_update after_validation after_validation_on_create after_validation_on_update
        syn keyword rubyPadrinoARCallbackMethod around_create around_destroy around_save around_update
        syn keyword rubyPadrinoARCallbackMethod after_commit after_find after_initialize after_rollback after_touch
        syn keyword rubyPadrinoARClassMethod attr_accessible attr_protected establish_connection set_inheritance_column set_locking_column set_primary_key set_sequence_name set_table_name
        syn keyword rubyPadrinoARValidationMethod validate validates validate_on_create validate_on_update validates_acceptance_of validates_associated validates_confirmation_of validates_each validates_exclusion_of validates_format_of validates_inclusion_of validates_length_of validates_numericality_of validates_presence_of validates_size_of validates_uniqueness_of
        syn keyword rubyPadrinoMethod logger
      endif
      if buffer.type_name('model-mongoid')
        syn keyword rubyPadrinoMethod field index scope default_scope attr_accessible attr_protected attr_readonly embeds_many embedded_in embeds_one accepts_nested_attributes_for belongs_to has_many has_one recursively_embeds_many
        syn keyword rubyPadrinoMethod after_initialize after_build before_validation after_validation before_create around_create after_create before_update around_update after_update before_save around_save after_save before_destroy around_destroy after_destroy
        syn keyword rubyPadrinoARValidationMethod validate validates validate_on_create validate_on_update validates_acceptance_of validates_associated validates_confirmation_of validates_each validates_exclusion_of validates_format_of validates_inclusion_of validates_length_of validates_numericality_of validates_presence_of validates_size_of validates_uniqueness_of
      endif
      if buffer.type_name('model-aro')
        syn keyword rubyPadrinoARMethod observe
      endif
      if buffer.type_name('mailer')
        syn keyword rubyPadrinoMethod logger url_for polymorphic_path polymorphic_url email
        syn keyword rubyPadrinoRenderMethod mail render partial
        syn keyword rubyPadrinoControllerMethod attachments default defaults helper helper_attr helper_method to subject from content_type
      endif
      if buffer.type_name('controller','view','helper')
        syn keyword rubyPadrinoMethod params request response session headers cookies flash content_type
        syn keyword rubyPadrinoRenderMethod render redirect partial
        syn keyword rubyPadrinoMethod logger polymorphic_path polymorphic_url
      endif
      if buffer.type_name('helper','view')
        exe "syn keyword rubyPadrinoHelperMethod ".s:gsub(s:helpermethods(),'<%(content_for|select)\s+','')
        syn match rubyPadrinoHelperMethod '\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!'
        syn match rubyPadrinoHelperMethod '\<\%(content_for?\=\|current_page?\)'
        syn match rubyPadrinoViewMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\|controller\)\>'
        syn keyword rubyKeyword yield_content
        if buffer.type_name('view-partial')
          syn keyword rubyPadrinoMethod local_assigns
        endif
      elseif buffer.type_name('controller')
        syn keyword rubyPadrinoControllerMethod get post delete patch put
        syn keyword rubyPadrinoControllerMethod helper helper_attr helper_method filter layout url_for serialize exempt_from_layout filter_parameter_logging hide_action cache_sweeper protect_from_forgery caches_page cache_page caches_action expire_page expire_action rescue_from
        syn keyword rubyPadrinoRenderMethod head redirect_to render_to_string respond_with halt
        syn match   rubyPadrinoRenderMethod '\<respond_to\>?\@!'
        syn keyword rubyPadrinoFilterMethod before_filter append_before_filter prepend_before_filter after_filter append_after_filter prepend_after_filter around_filter append_around_filter prepend_around_filter skip_before_filter skip_after_filter
        syn keyword rubyPadrinoFilterMethod verify
      endif
      if buffer.type_name('db-migration','db-schema')
        syn keyword rubyPadrinoMigrationMethod create_table change_table drop_table rename_table add_column rename_column change_column change_column_default remove_column add_index remove_index execute
      endif
      if buffer.type_name('test')
        if !empty(padrino#app().user_assertions())
          exe "syn keyword rubyPadrinoUserMethod ".join(padrino#app().user_assertions())
        endif
        syn keyword rubyPadrinoTestMethod add_assertion assert assert_block assert_equal assert_in_delta assert_instance_of assert_kind_of assert_match assert_nil assert_no_match assert_not_equal assert_not_nil assert_not_same assert_nothing_raised assert_nothing_thrown assert_operator assert_raise assert_respond_to assert_same assert_send assert_throws assert_recognizes assert_generates assert_routing flunk fixtures fixture_path use_transactional_fixtures use_instantiated_fixtures assert_difference assert_no_difference assert_valid
        syn keyword rubyPadrinoTestMethod test setup teardown
        if !buffer.type_name('test-unit')
          syn match   rubyPadrinoTestControllerMethod  '\.\@<!\<\%(get\|post\|put\|delete\|head\|process\|assigns\)\>'
          syn keyword rubyPadrinoTestControllerMethod get_via_redirect post_via_redirect put_via_redirect delete_via_redirect request_via_redirect
          syn keyword rubyPadrinoTestControllerMethod assert_response assert_redirected_to assert_template assert_recognizes assert_generates assert_routing assert_dom_equal assert_dom_not_equal assert_select assert_select_rjs assert_select_encoded assert_select_email assert_tag assert_no_tag
        endif
      elseif buffer.type_name('spec')
        syn keyword rubyPadrinoTestMethod describe context it its specify shared_examples_for it_should_behave_like before after subject fixtures controller_name helper_name
        syn match rubyPadrinoTestMethod '\<let\>!\='
        syn keyword rubyPadrinoTestMethod violated pending expect double mock mock_model stub_model
        syn match rubyPadrinoTestMethod '\.\@<!\<stub\>!\@!'
        if !buffer.type_name('spec-model')
          syn match   rubyPadrinoTestControllerMethod  '\.\@<!\<\%(get\|post\|put\|delete\|head\|process\|assigns\)\>'
          syn keyword rubyPadrinoTestControllerMethod  integrate_views
          syn keyword rubyPadrinoMethod params request response session flash
          syn keyword rubyPadrinoMethod polymorphic_path polymorphic_url
        endif
      endif
      if buffer.type_name('task')
        syn match rubyPadrinoRakeMethod '^\s*\zs\%(task\|file\|namespace\|desc\|before\|after\|on\)\>\%(\s*=\)\@!'
      endif
      if buffer.type_name('model-awss')
        syn keyword rubyPadrinoMethod member
      endif
      if buffer.type_name('config-routes')
        syn match rubyPadrinoMethod '\.\zs\%(connect\|named_route\)\>'
        syn keyword rubyPadrinoMethod match get put post delete redirect root resource resources collection member nested scope namespace controller constraints
      endif
      syn keyword rubyPadrinoMethod debugger
      syn keyword rubyPadrinoMethod alias_attribute alias_method_chain attr_accessor_with_default attr_internal attr_internal_accessor attr_internal_reader attr_internal_writer delegate mattr_accessor mattr_reader mattr_writer superclass_delegating_accessor superclass_delegating_reader superclass_delegating_writer
      syn keyword rubyPadrinoMethod cattr_accessor cattr_reader cattr_writer class_inheritable_accessor class_inheritable_array class_inheritable_array_writer class_inheritable_hash class_inheritable_hash_writer class_inheritable_option class_inheritable_reader class_inheritable_writer inheritable_attributes read_inheritable_attribute reset_inheritable_attributes write_inheritable_array write_inheritable_attribute write_inheritable_hash
      syn keyword rubyPadrinoInclude require_dependency gem

      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:order\s*=>\s*\)\@<="+ skip=+\\\\\|\\"+ end=+"+ contains=@rubyStringSpecial,padrinoOrderSpecial
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:order\s*=>\s*\)\@<='+ skip=+\\\\\|\\'+ end=+'+ contains=@rubyStringSpecial,padrinoOrderSpecial
      syn match   padrinoOrderSpecial +\c\<\%(DE\|A\)SC\>+ contained
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:conditions\s*=>\s*\[\s*\)\@<="+ skip=+\\\\\|\\"+ end=+"+ contains=@rubyStringSpecial,padrinoConditionsSpecial
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+\%(:conditions\s*=>\s*\[\s*\)\@<='+ skip=+\\\\\|\\'+ end=+'+ contains=@rubyStringSpecial,padrinoConditionsSpecial
      syn match   padrinoConditionsSpecial +?\|:\h\w*+ contained
      syn cluster rubyNotTop add=padrinoOrderSpecial,padrinoConditionsSpecial

      " XHTML highlighting inside %Q<>
      unlet! b:current_syntax
      let removenorend = !exists("g:html_no_rendering")
      let g:html_no_rendering = 1
      syn include @htmlTop syntax/xhtml.vim
      if removenorend
          unlet! g:html_no_rendering
      endif
      let b:current_syntax = "ruby"
      " Restore syn sync, as best we can
      if !exists("g:ruby_minlines")
        let g:ruby_minlines = 50
      endif
      syn sync fromstart
      exe "syn sync minlines=" . g:ruby_minlines
      syn case match
      syn region  rubyString   matchgroup=rubyStringDelimiter start=+%Q\=<+ end=+>+ contains=@htmlTop,@rubyStringSpecial
      syn cluster htmlArgCluster add=@rubyStringSpecial
      syn cluster htmlPreProc    add=@rubyStringSpecial

    elseif &syntax == 'eruby' || &syntax == 'haml'
      syn case match
      if classes != ''
        exe 'syn keyword '.&syntax.'PadrinoUserClass '.classes.' contained containedin=@'.&syntax.'PadrinoRegions'
      endif
      if &syntax == 'haml'
        exe 'syn cluster hamlPadrinoRegions contains=hamlRubyCodeIncluded,hamlRubyCode,hamlRubyHash,@hamlEmbeddedRuby,rubyInterpolation'
      else
        exe 'syn cluster erubyPadrinoRegions contains=erubyOneLiner,erubyBlock,erubyExpression,rubyInterpolation'
      endif
      exe 'syn keyword '.&syntax.'PadrinoHelperMethod '.s:gsub(s:helpermethods(),'<%(content_for|select)\s+','').' contained containedin=@'.&syntax.'PadrinoRegions'
      exe 'syn match '.&syntax.'PadrinoHelperMethod "\<select\>\%(\s*{\|\s*do\>\|\s*(\=\s*&\)\@!" contained containedin=@'.&syntax.'PadrinoRegions'
      exe 'syn match '.&syntax.'PadrinoHelperMethod "\<\%(content_for?\=\|current_page?\)" contained containedin=@'.&syntax.'PadrinoRegions'
      exe 'syn keyword '.&syntax.'PadrinoMethod debugger logger polymorphic_path polymorphic_url contained containedin=@'.&syntax.'PadrinoRegions'
      exe 'syn keyword '.&syntax.'PadrinoMethod params request response session headers cookies flash contained containedin=@'.&syntax.'PadrinoRegions'
      exe 'syn match '.&syntax.'PadrinoViewMethod "\.\@<!\<\(h\|html_escape\|u\|url_encode\|controller\)\>" contained containedin=@'.&syntax.'PadrinoRegions'
      exe 'syn keyword rubyKeyword yield_content'
      if buffer.type_name('view-partial')
        exe 'syn keyword '.&syntax.'PadrinoMethod local_assigns contained containedin=@'.&syntax.'PadrinoRegions'
      endif
      exe 'syn keyword '.&syntax.'PadrinoRenderMethod render partial contained containedin=@'.&syntax.'PadrinoRegions'
      exe 'syn case match'
      set isk+=$
      exe 'syn keyword javascriptPadrinoFunction contained '.s:javascript_functions
      exe 'syn cluster htmlJavaScript add=javascriptPadrinoFunction'
    elseif &syntax == "yaml"
      syn case match
      " Modeled after syntax/eruby.vim
      unlet! b:current_syntax
      let g:main_syntax = 'eruby'
      syn include @rubyTop syntax/ruby.vim
      unlet g:main_syntax
      syn cluster yamlPadrinoRegions contains=yamlPadrinoOneLiner,yamlPadrinoBlock,yamlPadrinoExpression
      syn region  yamlPadrinoOneLiner   matchgroup=yamlPadrinoDelimiter start="^%%\@!" end="$"  contains=@rubyPadrinoTop	containedin=ALLBUT,@yamlPadrinoRegions,yamlPadrinoComment keepend oneline
      syn region  yamlPadrinoBlock      matchgroup=yamlPadrinoDelimiter start="<%%\@!" end="%>" contains=@rubyTop		containedin=ALLBUT,@yamlPadrinoRegions,yamlPadrinoComment
      syn region  yamlPadrinoExpression matchgroup=yamlPadrinoDelimiter start="<%="    end="%>" contains=@rubyTop		containedin=ALLBUT,@yamlPadrinoRegions,yamlPadrinoComment
      syn region  yamlPadrinoComment    matchgroup=yamlPadrinoDelimiter start="<%#"    end="%>" contains=rubyTodo,@Spell	containedin=ALLBUT,@yamlPadrinoRegions,yamlPadrinoComment keepend
      syn match yamlPadrinoMethod '\.\@<!\<\(h\|html_escape\|u\|url_encode\)\>' contained containedin=@yamlPadrinoRegions
      if classes != ''
        exe "syn keyword yamlPadrinoUserClass ".classes." contained containedin=@yamlPadrinoRegions"
      endif
      let b:current_syntax = "yaml"
    elseif &syntax == "html"
      syn case match
      set isk+=$
      exe "syn keyword javascriptPadrinoFunction contained ".s:javascript_functions
      syn cluster htmlJavaScript add=javascriptPadrinoFunction
    elseif &syntax == "javascript" || &syntax == "coffee"
      " The syntax file included with Vim incorrectly sets syn case ignore.
      syn case match
      set isk+=$
      exe "syn keyword javascriptPadrinoFunction ".s:javascript_functions

    endif
  endif
  call s:HiDefaults()
endfunction

function! s:HiDefaults()
  hi def link rubyPadrinoAPIMethod              rubyPadrinoMethod
  hi def link rubyPadrinoARAssociationMethod    rubyPadrinoARMethod
  hi def link rubyPadrinoARCallbackMethod       rubyPadrinoARMethod
  hi def link rubyPadrinoARClassMethod          rubyPadrinoARMethod
  hi def link rubyPadrinoARValidationMethod     rubyPadrinoARMethod
  hi def link rubyPadrinoARMethod               rubyPadrinoMethod
  hi def link rubyPadrinoRenderMethod           rubyPadrinoMethod
  hi def link rubyPadrinoHelperMethod           rubyPadrinoMethod
  hi def link rubyPadrinoViewMethod             rubyPadrinoMethod
  hi def link rubyPadrinoMigrationMethod        rubyPadrinoMethod
  hi def link rubyPadrinoControllerMethod       rubyPadrinoMethod
  hi def link rubyPadrinoFilterMethod           rubyPadrinoMethod
  hi def link rubyPadrinoTestControllerMethod   rubyPadrinoTestMethod
  hi def link rubyPadrinoTestMethod             rubyPadrinoMethod
  hi def link rubyPadrinoRakeMethod             rubyPadrinoMethod
  hi def link rubyPadrinoMethod                 padrinoMethod
  hi def link rubyPadrinoInclude                rubyInclude
  hi def link rubyPadrinoUserClass              padrinoUserClass
  hi def link rubyPadrinoUserMethod             padrinoUserMethod
  hi def link erubyPadrinoHelperMethod          erubyPadrinoMethod
  hi def link erubyPadrinoViewMethod            erubyPadrinoMethod
  hi def link erubyPadrinoRenderMethod          erubyPadrinoMethod
  hi def link erubyPadrinoMethod                padrinoMethod
  hi def link erubyPadrinoUserMethod            padrinoUserMethod
  hi def link erubyPadrinoUserClass             padrinoUserClass
  hi def link hamlPadrinoHelperMethod           hamlPadrinoMethod
  hi def link hamlPadrinoViewMethod             hamlPadrinoMethod
  hi def link hamlPadrinoRenderMethod           hamlPadrinoMethod
  hi def link hamlPadrinoMethod                 padrinoMethod
  hi def link hamlPadrinoUserMethod             padrinoUserMethod
  hi def link hamlPadrinoUserClass              padrinoUserClass
  hi def link padrinoUserMethod                 padrinoMethod
  hi def link yamlPadrinoDelimiter              Delimiter
  hi def link yamlPadrinoMethod                 padrinoMethod
  hi def link yamlPadrinoComment                Comment
  hi def link yamlPadrinoUserClass              padrinoUserClass
  hi def link yamlPadrinoUserMethod             padrinoUserMethod
  hi def link javascriptPadrinoFunction         padrinoMethod
  hi def link padrinoUserClass                  padrinoClass
  hi def link padrinoMethod                     Function
  hi def link padrinoClass                      Type
  hi def link padrinoOrderSpecial               padrinoStringSpecial
  hi def link padrinoConditionsSpecial          padrinoStringSpecial
  hi def link padrinoStringSpecial              Identifier
endfunction

function! padrino#log_syntax()
  if has('conceal')
    syn match padrinologEscape      '\e\[[0-9;]*m' conceal
    syn match padrinologEscapeMN    '\e\[[0-9;]*m' conceal nextgroup=padrinologModelNum,padrinologEscapeMN skipwhite contained
    syn match padrinologEscapeSQL   '\e\[[0-9;]*m' conceal nextgroup=padrinologSQL,padrinologEscapeSQL skipwhite contained
  else
    syn match padrinologEscape      '\e\[[0-9;]*m'
    syn match padrinologEscapeMN    '\e\[[0-9;]*m' nextgroup=padrinologModelNum,padrinologEscapeMN skipwhite contained
    syn match padrinologEscapeSQL   '\e\[[0-9;]*m' nextgroup=padrinologSQL,padrinologEscapeSQL skipwhite contained
  endif
  syn match   padrinologRender      '\%(^\s*\%(\e\[[0-9;]*m\)\=\)\@<=\%(Processing\|Rendering\|Rendered\|Redirected\|Completed\)\>'
  syn match   padrinologComment     '^\s*# .*'
  syn match   padrinologModel       '\%(^\s*\%(\e\[[0-9;]*m\)\=\)\@<=\u\%(\w\|:\)* \%(Load\%( Including Associations\| IDs For Limited Eager Loading\)\=\|Columns\|Count\|Create\|Update\|Destroy\|Delete all\)\>' skipwhite nextgroup=padrinologModelNum,padrinologEscapeMN
  syn match   padrinologModel       '\%(^\s*\%(\e\[[0-9;]*m\)\=\)\@<=SQL\>' skipwhite nextgroup=padrinologModelNum,padrinologEscapeMN
  syn region  padrinologModelNum    start='(' end=')' contains=padrinologNumber contained skipwhite nextgroup=padrinologSQL,padrinologEscapeSQL
  syn match   padrinologSQL         '\u[^\e]*' contained
  " Destroy generates multiline SQL, ugh
  syn match   padrinologSQL         '\%(^ \%(\e\[[0-9;]*m\)\=\)\@<=\%(FROM\|WHERE\|ON\|AND\|OR\|ORDER\) .*$'
  syn match   padrinologNumber      '\<\d\+\>%'
  syn match   padrinologNumber      '[ (]\@<=\<\d\+\.\d\+\>\.\@!'
  syn region  padrinologString      start='"' skip='\\"' end='"' oneline contained
  syn region  padrinologHash        start='{' end='}' oneline contains=padrinologHash,padrinologString
  syn match   padrinologIP          '\<\d\{1,3\}\%(\.\d\{1,3}\)\{3\}\>'
  syn match   padrinologTimestamp   '\<\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\>'
  syn match   padrinologSessionID   '\<\x\{32\}\>'
  syn match   padrinologIdentifier  '^\s*\%(Session ID\|Parameters\)\ze:'
  syn match   padrinologSuccess     '\<2\d\d \u[A-Za-z0-9 ]*\>'
  syn match   padrinologRedirect    '\<3\d\d \u[A-Za-z0-9 ]*\>'
  syn match   padrinologError       '\<[45]\d\d \u[A-Za-z0-9 ]*\>'
  syn match   padrinologError       '^DEPRECATION WARNING\>'
  syn keyword padrinologHTTP        OPTIONS GET HEAD POST PUT DELETE TRACE CONNECT
  syn region  padrinologStackTrace  start=":\d\+:in `\w\+'$" end="^\s*$" keepend fold
  hi def link padrinologEscapeMN    padrinologEscape
  hi def link padrinologEscapeSQL   padrinologEscape
  hi def link padrinologEscape      Ignore
  hi def link padrinologComment     Comment
  hi def link padrinologRender      Keyword
  hi def link padrinologModel       Type
  hi def link padrinologSQL         PreProc
  hi def link padrinologNumber      Number
  hi def link padrinologString      String
  hi def link padrinologSessionID   Constant
  hi def link padrinologIdentifier  Identifier
  hi def link padrinologRedirect    padrinologSuccess
  hi def link padrinologSuccess     Special
  hi def link padrinologError       Error
  hi def link padrinologHTTP        Special
endfunction

" }}}1
" Statusline {{{1

function! s:addtostatus(letter,status)
  let status = a:status
  if status !~ 'padrino' && status !~ '^%!' && g:padrino_statusline
    let   status=substitute(status,'\C%'.tolower(a:letter),'%'.tolower(a:letter).'%{padrino#statusline()}','')
    if status !~ 'padrino'
      let status=substitute(status,'\C%'.toupper(a:letter),'%'.toupper(a:letter).'%{padrino#STATUSLINE()}','')
    endif
  endif
  return status
endfunction

function! s:BufInitStatusline()
  if g:padrino_statusline
    if &l:statusline == ''
      let &l:statusline = &g:statusline
    endif
    if &l:statusline == ''
      let &l:statusline='%<%f %h%m%r%='
      if &ruler
        let &l:statusline .= '%-14.(%l,%c%V%) %P'
      endif
    endif
    let &l:statusline = s:InjectIntoStatusline(&l:statusline)
  endif
endfunction

function! s:InitStatusline()
  if g:padrino_statusline
    if &g:statusline == ''
      let &g:statusline='%<%f %h%m%r%='
      if &ruler
        let &g:statusline .= '%-16( %l,%c-%v %)%P'
      endif
    endif
    let &g:statusline = s:InjectIntoStatusline(&g:statusline)
  endif
endfunction

function! s:InjectIntoStatusline(status)
  let status = a:status
  if status !~ 'padrino'
    let status = s:addtostatus('y',status)
    let status = s:addtostatus('r',status)
    let status = s:addtostatus('m',status)
    let status = s:addtostatus('w',status)
    let status = s:addtostatus('h',status)
    if status !~ 'padrino'
      let status=substitute(status,'%=','%{padrino#statusline()}%=','')
    endif
    if status !~ 'padrino' && status != ''
      let status .= '%{padrino#statusline()}'
    endif
  endif
  return status
endfunction

function! padrino#statusline(...)
  if exists("b:padrino_root")
    let t = padrino#buffer().type_name()
    if t != "" && a:0 && a:1
      return "[Padrino-".t."]"
    else
      return "[Padrino]"
    endif
  else
    return ""
  endif
endfunction

function! padrino#STATUSLINE(...)
  if exists("b:padrino_root")
    let t = padrino#buffer().type_name()
    if t != "" && a:0 && a:1
      return ",PADRINO-".toupper(t)
    else
      return ",PADRINO"
    endif
  else
    return ""
  endif
endfunction

" }}}1
" Mappings {{{1

function! s:BufMappings()
  nnoremap <buffer> <silent> <Plug>PadrinoAlternate  :<C-U>A<CR>
  nnoremap <buffer> <silent> <Plug>PadrinoRelated    :<C-U>R<CR>
  nnoremap <buffer> <silent> <Plug>PadrinoFind       :<C-U>REfind<CR>
  nnoremap <buffer> <silent> <Plug>PadrinoSplitFind  :<C-U>RSfind<CR>
  nnoremap <buffer> <silent> <Plug>PadrinoVSplitFind :<C-U>RVfind<CR>
  nnoremap <buffer> <silent> <Plug>PadrinoTabFind    :<C-U>RTfind<CR>
  if g:padrino_mappings
    if !hasmapto("<Plug>PadrinoFind")
      nmap <buffer> gf              <Plug>PadrinoFind
    endif
    if !hasmapto("<Plug>PadrinoSplitFind")
      nmap <buffer> <C-W>f          <Plug>PadrinoSplitFind
    endif
    if !hasmapto("<Plug>PadrinoTabFind")
      nmap <buffer> <C-W>gf         <Plug>PadrinoTabFind
    endif
    if !hasmapto("<Plug>PadrinoAlternate")
      nmap <buffer> [f              <Plug>PadrinoAlternate
    endif
    if !hasmapto("<Plug>PadrinoRelated")
      nmap <buffer> ]f              <Plug>PadrinoRelated
    endif
    if exists("$CREAM")
      imap <buffer> <C-CR> <C-O><Plug>PadrinoFind
      imap <buffer> <M-[>  <C-O><Plug>PadrinoAlternate
      imap <buffer> <M-]>  <C-O><Plug>PadrinoRelated
    endif
  endif
  " SelectBuf you're a dirty hack
  let v:errmsg = ""
endfunction

" }}}1
" Database {{{1

function! s:extractdbvar(str,arg)
  return matchstr("\n".a:str."\n",'\n'.a:arg.'=\zs.\{-\}\ze\n')
endfunction

function! s:app_dbext_settings(environment) dict
  if self.cache.needs('dbext_settings')
    call self.cache.set('dbext_settings',{})
  endif
  let cache = self.cache.get('dbext_settings')
  if !has_key(cache,a:environment)
    let dict = {}
    if self.has_file("config/database.yml")
      let cmdb = 'require %{yaml}; File.open(%q{'.self.path().'/config/database.yml}) {|f| y = YAML::load(f); e = y[%{'
      let cmde = '}]; i=0; e=y[e] while e.respond_to?(:to_str) && (i+=1)<16; e.each{|k,v|puts k.to_s+%{=}+v.to_s}}'
      let out = self.lightweight_ruby_eval(cmdb.a:environment.cmde)
      let adapter = s:extractdbvar(out,'adapter')
      let adapter = get({'mysql2': 'mysql', 'postgresql': 'pgsql', 'sqlite3': 'sqlite', 'sqlserver': 'sqlsrv', 'sybase': 'asa', 'oci': 'ora'},adapter,adapter)
      let dict['type'] = toupper(adapter)
      let dict['user'] = s:extractdbvar(out,'username')
      let dict['passwd'] = s:extractdbvar(out,'password')
      if dict['passwd'] == '' && adapter == 'mysql'
        " Hack to override password from .my.cnf
        let dict['extra'] = ' --password='
      else
        let dict['extra'] = ''
      endif
      let dict['dbname'] = s:extractdbvar(out,'database')
      if dict['dbname'] == ''
        let dict['dbname'] = s:extractdbvar(out,'dbfile')
      endif
      if dict['dbname'] != '' && dict['dbname'] !~ '^:' && adapter =~? '^sqlite'
        let dict['dbname'] = self.path(dict['dbname'])
      endif
      let dict['profile'] = ''
      let dict['srvname'] = s:extractdbvar(out,'host')
      let dict['host'] = s:extractdbvar(out,'host')
      let dict['port'] = s:extractdbvar(out,'port')
      let dict['dsnname'] = s:extractdbvar(out,'dsn')
      if dict['host'] =~? '^\cDBI:'
        if dict['host'] =~? '\c\<Trusted[_ ]Connection\s*=\s*yes\>'
          let dict['integratedlogin'] = 1
        endif
        let dict['host'] = matchstr(dict['host'],'\c\<\%(Server\|Data Source\)\s*=\s*\zs[^;]*')
      endif
      call filter(dict,'v:val != ""')
    endif
    let cache[a:environment] = dict
  endif
  return cache[a:environment]
endfunction

function! s:BufDatabase(...)
  if exists("s:lock_database") || !exists('g:loaded_dbext') || !exists('b:padrino_root')
    return
  endif
  let self = padrino#app()
  let s:lock_database = 1
  if (a:0 && a:1 > 1)
    call self.cache.clear('dbext_settings')
  endif
  if (a:0 > 1 && a:2 != '')
    let env = a:2
  else
    let env = s:environment()
  endif
  if (!self.cache.has('dbext_settings') || !has_key(self.cache.get('dbext_settings'),env)) && (a:0 ? a:1 : 0) <= 0
    unlet! s:lock_database
    return
  endif
  let dict = self.dbext_settings(env)
  for key in ['type', 'profile', 'bin', 'user', 'passwd', 'dbname', 'srvname', 'host', 'port', 'dsnname', 'extra', 'integratedlogin']
    let b:dbext_{key} = get(dict,key,'')
  endfor
  if b:dbext_type == 'PGSQL'
    let $PGPASSWORD = b:dbext_passwd
  elseif exists('$PGPASSWORD')
    let $PGPASSWORD = ''
  endif
  unlet! s:lock_database
endfunction

call s:add_methods('app', ['dbext_settings'])

" }}}1
" Abbreviations {{{1

function! s:selectiveexpand(pat,good,default,...)
  if a:0 > 0
    let nd = a:1
  else
    let nd = ""
  endif
  let c = nr2char(getchar(0))
  let good = a:good
  if c == "" " ^]
    return s:sub(good.(a:0 ? " ".a:1 : ''),'\s+$','')
  elseif c == "\t"
    return good.(a:0 ? " ".a:1 : '')
  elseif c =~ a:pat
    return good.c.(a:0 ? a:1 : '')
  else
    return a:default.c
  endif
endfunction

function! s:TheCWord()
  let l = s:linepeak()
  if l =~ '\<\%(find\|first\|last\|all\|paginate\)\>'
    return s:selectiveexpand('..',':conditions => ',':c')
  elseif l =~ '\<render\s*(\=\s*:partial\s*=>\s*'
    return s:selectiveexpand('..',':collection => ',':c')
  elseif l =~ '\<\%(url_for\|link_to\|form_tag\)\>' || l =~ ':url\s*=>\s*{\s*'
    return s:selectiveexpand('..',':controller => ',':c')
  else
    return s:selectiveexpand('..',':conditions => ',':c')
  endif
endfunction

function! s:AddSelectiveExpand(abbr,pat,expn,...)
  let expn  = s:gsub(s:gsub(a:expn        ,'[\"|]','\\&'),'\<','\\<Lt>')
  let expn2 = s:gsub(s:gsub(a:0 ? a:1 : '','[\"|]','\\&'),'\<','\\<Lt>')
  if a:0
    exe "inoreabbrev <buffer> <silent> ".a:abbr." <C-R>=<SID>selectiveexpand(".string(a:pat).",\"".expn."\",".string(a:abbr).",\"".expn2."\")<CR>"
  else
    exe "inoreabbrev <buffer> <silent> ".a:abbr." <C-R>=<SID>selectiveexpand(".string(a:pat).",\"".expn."\",".string(a:abbr).")<CR>"
  endif
endfunction

function! s:AddTabExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'..',a:expn)
endfunction

function! s:AddBracketExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'[[.]',a:expn)
endfunction

function! s:AddColonExpand(abbr,expn)
  call s:AddSelectiveExpand(a:abbr,'[:.]',a:expn)
endfunction

function! s:AddParenExpand(abbr,expn,...)
  if a:0
    call s:AddSelectiveExpand(a:abbr,'(',a:expn,a:1)
  else
    call s:AddSelectiveExpand(a:abbr,'(',a:expn,'')
  endif
endfunction

function! s:BufAbbreviations()
  command! -buffer -bar -nargs=* -bang Rabbrev :call s:Abbrev(<bang>0,<f-args>)
  " Some of these were cherry picked from the TextMate snippets
  if g:padrino_abbreviations
    let buffer = padrino#buffer()
    " Limit to the right filetypes.  But error on the liberal side
    if buffer.type_name('controller','view','helper','test-functional','test-integration')
      Rabbrev pa[ params
      Rabbrev rq[ request
      Rabbrev rs[ response
      Rabbrev se[ session
      Rabbrev hd[ headers
      Rabbrev coo[ cookies
      Rabbrev fl[ flash
      Rabbrev rr( render
      Rabbrev ra( render :action\ =>\ 
      Rabbrev rc( render :controller\ =>\ 
      Rabbrev rf( render :file\ =>\ 
      Rabbrev ri( render :inline\ =>\ 
      Rabbrev rj( render :json\ =>\ 
      Rabbrev rl( render :layout\ =>\ 
      Rabbrev rp( render :partial\ =>\ 
      Rabbrev rt( render :text\ =>\ 
      Rabbrev rx( render :xml\ =>\ 
    endif
    if buffer.type_name('view','helper')
      Rabbrev dotiw distance_of_time_in_words
      Rabbrev taiw  time_ago_in_words
    endif
    if buffer.type_name('controller')
      Rabbrev re(  redirect_to
      Rabbrev rea( redirect_to :action\ =>\ 
      Rabbrev rec( redirect_to :controller\ =>\ 
      Rabbrev rst( respond_to
    endif
    if buffer.type_name() ==# 'model' || buffer.type_name('model-arb')
      Rabbrev bt(    belongs_to
      Rabbrev ho(    has_one
      Rabbrev hm(    has_many
      Rabbrev habtm( has_and_belongs_to_many
      Rabbrev co(    composed_of
      Rabbrev va(    validates_associated
      Rabbrev vb(    validates_acceptance_of
      Rabbrev vc(    validates_confirmation_of
      Rabbrev ve(    validates_exclusion_of
      Rabbrev vf(    validates_format_of
      Rabbrev vi(    validates_inclusion_of
      Rabbrev vl(    validates_length_of
      Rabbrev vn(    validates_numericality_of
      Rabbrev vp(    validates_presence_of
      Rabbrev vu(    validates_uniqueness_of
    endif
    if buffer.type_name('db-migration','db-schema')
      Rabbrev mac(  add_column
      Rabbrev mrnc( rename_column
      Rabbrev mrc(  remove_column
      Rabbrev mct(  create_table
      Rabbrev mcht( change_table
      Rabbrev mrnt( rename_table
      Rabbrev mdt(  drop_table
      Rabbrev mcc(  t.column
    endif
    if buffer.type_name('test')
      Rabbrev ase(  assert_equal
      Rabbrev asko( assert_kind_of
      Rabbrev asnn( assert_not_nil
      Rabbrev asr(  assert_raise
      Rabbrev asre( assert_response
      Rabbrev art(  assert_redirected_to
    endif
    Rabbrev :a    :action\ =>\ 
    " hax
    Rabbrev :c    :co________\ =>\ 
    inoreabbrev <buffer> <silent> :c <C-R>=<SID>TheCWord()<CR>
    Rabbrev :i    :id\ =>\ 
    Rabbrev :o    :object\ =>\ 
    Rabbrev :p    :partial\ =>\ 
    Rabbrev logd( logger.debug
    Rabbrev logi( logger.info
    Rabbrev logw( logger.warn
    Rabbrev loge( logger.error
    Rabbrev logf( logger.fatal
    Rabbrev fi(   find
    Rabbrev AR::  ActiveRecord
    Rabbrev AV::  ActionView
    Rabbrev AC::  ActionController
    Rabbrev AD::  ActionDispatch
    Rabbrev AS::  ActiveSupport
    Rabbrev AM::  ActionMailer
    Rabbrev AO::  ActiveModel
    Rabbrev AE::  ActiveResource
    Rabbrev AWS:: ActionWebService
  endif
endfunction

function! s:Abbrev(bang,...) abort
  if !exists("b:padrino_abbreviations")
    let b:padrino_abbreviations = {}
  endif
  if a:0 > 3 || (a:bang && (a:0 != 1))
    return s:error("Rabbrev: invalid arguments")
  endif
  if a:0 == 0
    for key in sort(keys(b:padrino_abbreviations))
      echo key . join(b:padrino_abbreviations[key],"\t")
    endfor
    return
  endif
  let lhs = a:1
  let root = s:sub(lhs,'%(::|\(|\[)$','')
  if a:bang
    if has_key(b:padrino_abbreviations,root)
      call remove(b:padrino_abbreviations,root)
    endif
    exe "iunabbrev <buffer> ".root
    return
  endif
  if a:0 > 3 || a:0 < 2
    return s:error("Rabbrev: invalid arguments")
  endif
  let rhs = a:2
  if has_key(b:padrino_abbreviations,root)
    call remove(b:padrino_abbreviations,root)
  endif
  if lhs =~ '($'
    let b:padrino_abbreviations[root] = ["(", rhs . (a:0 > 2 ? "\t".a:3 : "")]
    if a:0 > 2
      call s:AddParenExpand(root,rhs,a:3)
    else
      call s:AddParenExpand(root,rhs)
    endif
    return
  endif
  if a:0 > 2
    return s:error("Rabbrev: invalid arguments")
  endif
  if lhs =~ ':$'
    call s:AddColonExpand(root,rhs)
  elseif lhs =~ '\[$'
    call s:AddBracketExpand(root,rhs)
  elseif lhs =~ '\w$'
    call s:AddTabExpand(lhs,rhs)
  else
    return s:error("Rabbrev: unimplemented")
  endif
  let b:padrino_abbreviations[root] = [matchstr(lhs,'\W*$'),rhs]
endfunction

" }}}1
" Settings {{{1

function! s:Set(bang,...)
  let c = 1
  let defscope = ''
  for arg in a:000
    if arg =~? '^<[abgl]\=>$'
      let defscope = (matchstr(arg,'<\zs.*\ze>'))
    elseif arg !~ '='
      if defscope != '' && arg !~ '^\w:'
        let arg = defscope.':'.opt
      endif
      let val = s:getopt(arg)
      if val == '' && !has_key(s:opts(),arg)
        call s:error("No such padrino.vim option: ".arg)
      else
        echo arg."=".val
      endif
    else
      let opt = matchstr(arg,'[^=]*')
      let val = s:sub(arg,'^[^=]*\=','')
      if defscope != '' && opt !~ '^\w:'
        let opt = defscope.':'.opt
      endif
      call s:setopt(opt,val)
    endif
  endfor
endfunction

function! s:getopt(opt,...)
  let app = padrino#app()
  let opt = a:opt
  if a:0
    let scope = a:1
  elseif opt =~ '^[abgl]:'
    let scope = tolower(matchstr(opt,'^\w'))
    let opt = s:sub(opt,'^\w:','')
  else
    let scope = 'abgl'
  endif
  let lnum = a:0 > 1 ? a:2 : line('.')
  if scope =~ 'l' && &filetype != 'ruby'
    let scope = s:sub(scope,'l','b')
  endif
  if scope =~ 'l'
    call s:LocalModelines(lnum)
  endif
  let var = s:sname().'_'.opt
  let lastmethod = s:lastmethod(lnum)
  if lastmethod == '' | let lastmethod = ' ' | endif
  " Get buffer option
  if scope =~ 'l' && exists('b:_'.var) && has_key(b:_{var},lastmethod)
    return b:_{var}[lastmethod]
  elseif exists('b:'.var) && (scope =~ 'b' || (scope =~ 'l' && lastmethod == ' '))
    return b:{var}
  elseif scope =~ 'a' && has_key(app,'options') && has_key(app.options,opt)
    return app.options[opt]
  elseif scope =~ 'g' && exists("g:".s:sname()."_".opt)
    return g:{var}
  else
    return ""
  endif
endfunction

function! s:setopt(opt,val)
  let app = padrino#app()
  if a:opt =~? '[abgl]:'
    let scope = matchstr(a:opt,'^\w')
    let opt = s:sub(a:opt,'^\w:','')
  else
    let scope = ''
    let opt = a:opt
  endif
  let defscope = get(s:opts(),opt,'a')
  if scope == ''
    let scope = defscope
  endif
  if &filetype != 'ruby' && (scope ==# 'B' || scope ==# 'l')
    let scope = 'b'
  endif
  let var = s:sname().'_'.opt
  if opt =~ '\W'
    return s:error("Invalid option ".a:opt)
  elseif scope ==# 'B' && defscope == 'l'
    if !exists('b:_'.var) | let b:_{var} = {} | endif
    let b:_{var}[' '] = a:val
  elseif scope =~? 'b'
    let b:{var} = a:val
  elseif scope =~? 'a'
    if !has_key(app,'options') | let app.options = {} | endif
    let app.options[opt] = a:val
  elseif scope =~? 'g'
    let g:{var} = a:val
  elseif scope =~? 'l'
    if !exists('b:_'.var) | let b:_{var} = {} | endif
    let lastmethod = s:lastmethod(lnum)
    let b:_{var}[lastmethod == '' ? ' ' : lastmethod] = a:val
  else
    return s:error("Invalid scope for ".a:opt)
  endif
endfunction

function! s:opts()
  return {'alternate': 'b', 'controller': 'b', 'gnu_screen': 'a', 'model': 'b', 'preview': 'l', 'task': 'b', 'related': 'l', 'root_url': 'a'}
endfunction

function! s:Complete_set(A,L,P)
  if a:A =~ '='
    let opt = matchstr(a:A,'[^=]*')
    return [opt."=".s:getopt(opt)]
  else
    let extra = matchstr(a:A,'^[abgl]:')
    return filter(sort(map(keys(s:opts()),'extra.v:val')),'s:startswith(v:val,a:A)')
  endif
  return []
endfunction

function! s:BufModelines()
  if !g:padrino_modelines
    return
  endif
  let lines = getline("$")."\n".getline(line("$")-1)."\n".getline(1)."\n".getline(2)."\n".getline(3)."\n"
  let pat = '\s\+\zs.\{-\}\ze\%(\n\|\s\s\|#{\@!\|%>\|-->\|$\)'
  let cnt = 1
  let mat    = matchstr(lines,'\C\<Rset'.pat)
  let matend = matchend(lines,'\C\<Rset'.pat)
  while mat != "" && cnt < 10
    let mat = s:sub(mat,'\s+$','')
    let mat = s:gsub(mat,'\|','\\|')
    if mat != ''
      silent! exe "Rset <B> ".mat
    endif
    let mat    = matchstr(lines,'\C\<Rset'.pat,matend)
    let matend = matchend(lines,'\C\<Rset'.pat,matend)
    let cnt += 1
  endwhile
endfunction

function! s:LocalModelines(lnum)
  if !g:padrino_modelines
    return
  endif
  let lbeg = s:lastmethodline(a:lnum)
  let lend = s:endof(lbeg)
  if lbeg == 0 || lend == 0
    return
  endif
  let lines = "\n"
  let lnum = lbeg
  while lnum < lend && lnum < lbeg + 5
    let lines .= getline(lnum) . "\n"
    let lnum += 1
  endwhile
  let pat = '\s\+\zs.\{-\}\ze\%(\n\|\s\s\|#{\@!\|%>\|-->\|$\)'
  let cnt = 1
  let mat    = matchstr(lines,'\C\<rset'.pat)
  let matend = matchend(lines,'\C\<rset'.pat)
  while mat != "" && cnt < 10
    let mat = s:sub(mat,'\s+$','')
    let mat = s:gsub(mat,'\|','\\|')
    if mat != ''
      silent! exe "Rset <l> ".mat
    endif
    let mat    = matchstr(lines,'\C\<rset'.pat,matend)
    let matend = matchend(lines,'\C\<rset'.pat,matend)
    let cnt += 1
  endwhile
endfunction

" }}}1
" Detection {{{1

function! s:app_source_callback(file) dict
  if self.cache.needs('existence')
    call self.cache.set('existence',{})
  endif
  let cache = self.cache.get('existence')
  if !has_key(cache,a:file)
    let cache[a:file] = self.has_file(a:file)
  endif
  if cache[a:file]
    sandbox source `=self.path(a:file)`
  endif
endfunction

call s:add_methods('app',['source_callback'])

function! PadrinoBufInit(path)
  let firsttime = !(exists("b:padrino_root") && b:padrino_root == a:path)
  let b:padrino_root = a:path
  if !has_key(s:apps,a:path)
    let s:apps[a:path] = deepcopy(s:app_prototype)
    let s:apps[a:path].root = a:path
  endif
  let app = s:apps[a:path]
  let buffer = padrino#buffer()
  " Apparently padrino#buffer().calculate_file_type() can be slow if the
  " underlying file system is slow (even though it doesn't really do anything
  " IO related).  This caching is a temporary hack; if it doesn't cause
  " problems it should probably be refactored.
  let b:padrino_cached_file_type = buffer.calculate_file_type()
  if g:padrino_history_size > 0
    if !exists("g:PADRINO_HISTORY")
      let g:PADRINO_HISTORY = ""
    endif
    let path = a:path
    let g:PADRINO_HISTORY = s:scrub(g:PADRINO_HISTORY,path)
    if has("win32")
      let g:PADRINO_HISTORY = s:scrub(g:PADRINO_HISTORY,s:gsub(path,'\\','/'))
    endif
    let path = fnamemodify(path,':p:~:h')
    let g:PADRINO_HISTORY = s:scrub(g:PADRINO_HISTORY,path)
    if has("win32")
      let g:PADRINO_HISTORY = s:scrub(g:PADRINO_HISTORY,s:gsub(path,'\\','/'))
    endif
    let g:PADRINO_HISTORY = path."\n".g:PADRINO_HISTORY
    let g:PADRINO_HISTORY = s:sub(g:PADRINO_HISTORY,'%(.{-}\n){,'.g:padrino_history_size.'}\zs.*','')
  endif
  call app.source_callback("config/syntax.vim")
  if &ft == "mason"
    setlocal filetype=eruby
  elseif &ft =~ '^\%(conf\|ruby\)\=$' && expand("%:e") =~ '^\%(rjs\|rxml\|builder\|rake\|mab\)$'
    setlocal filetype=ruby
  elseif &ft =~ '^\%(conf\|ruby\)\=$' && expand("%:t") =~ '^\%(\%(Rake\|Gem\|Cap\)file\|Isolate\)$'
    setlocal filetype=ruby
  elseif &ft =~ '^\%(liquid\)\=$' && expand("%:e") == "liquid"
    setlocal filetype=liquid
  elseif &ft =~ '^\%(haml\|x\=html\)\=$' && expand("%:e") == "haml"
    setlocal filetype=haml
  elseif &ft =~ '^\%(sass\|conf\)\=$' && expand("%:e") == "sass"
    setlocal filetype=sass
  elseif &ft =~ '^\%(scss\|conf\)\=$' && expand("%:e") == "scss"
    setlocal filetype=scss
  elseif &ft =~ '^\%(lesscss\|conf\)\=$' && expand("%:e") == "less"
    setlocal filetype=lesscss
  elseif &ft =~ '^\%(dryml\)\=$' && expand("%:e") == "dryml"
    setlocal filetype=dryml
  elseif (&ft == "" || v:version < 701) && expand("%:e") =~ '^\%(rhtml\|erb\)$'
    setlocal filetype=eruby
  elseif (&ft == "" || v:version < 700) && expand("%:e") == 'yml'
    setlocal filetype=yaml
  elseif &ft =~ '^\%(conf\|yaml\)\=$' && expand("%:t") =~ '\.yml\.example$'
    setlocal filetype=yaml
  elseif firsttime
    " Activate custom syntax
    let &syntax = &syntax
  endif
  if firsttime
    call s:BufInitStatusline()
  endif
  if expand('%:e') == 'log'
    nnoremap <buffer> <silent> R :checktime<CR>
    nnoremap <buffer> <silent> G :checktime<Bar>$<CR>
    nnoremap <buffer> <silent> q :bwipe<CR>
    setlocal modifiable filetype=padrinolog noswapfile autoread foldmethod=syntax
    if exists('+concealcursor')
      setlocal concealcursor=nc conceallevel=2
    else
      silent %s/\%(\e\[[0-9;]*m\|\r$\)//ge
    endif
    setlocal readonly nomodifiable
    $
  endif
  call s:BufSettings()
  call s:BufCommands()
  call s:BufAbbreviations()
  " snippetsEmu.vim
  if exists('g:loaded_snippet')
    silent! runtime! ftplugin/padrino_snippets.vim
    " filetype snippets need to come last for higher priority
    exe "silent! runtime! ftplugin/".&filetype."_snippets.vim"
  endif
  let t = padrino#buffer().type_name()
  let t = "-".t
  let f = '/'.PadrinoFilePath()
  if f =~ '[ !#$%\,]'
    let f = ''
  endif
  runtime! macros/padrino.vim
  silent doautocmd User Padrino
  if t != '-'
    exe "silent doautocmd User Padrino".s:gsub(t,'-','.')
  endif
  if f != ''
    exe "silent doautocmd User Padrino".f
  endif
  call app.source_callback("config/padrino.vim")
  call s:BufModelines()
  call s:BufMappings()
  return b:padrino_root
endfunction

function! s:SetBasePath()
  let self = padrino#buffer()
  if self.app().path() =~ '://'
    return
  endif
  let transformed_path = s:pathsplit(s:pathjoin([self.app().path()]))[0]
  let add_dot = self.getvar('&path') =~# '^\.\%(,\|$\)'
  let old_path = s:pathsplit(s:sub(self.getvar('&path'),'^\.%(,|$)',''))
  call filter(old_path,'!s:startswith(v:val,transformed_path)')

  let path = ['app', 'app/models', 'app/controllers', 'app/helpers', 'config', 'lib', 'app/views']
  if self.controller_name() != ''
    let path += ['app/views/'.self.controller_name(), 'public']
  endif
  if self.app().has('test')
    let path += ['test', 'test/unit', 'test/functional', 'test/integration']
  endif
  if self.app().has('spec')
    let path += ['spec', 'spec/models', 'spec/controllers', 'spec/helpers', 'spec/views', 'spec/lib', 'spec/requests', 'spec/integration']
  endif
  let path += ['app/*', 'vendor', 'vendor/plugins/*/lib', 'vendor/plugins/*/test', 'vendor/padrino/*/lib', 'vendor/padrino/*/test']
  call map(path,'self.app().path(v:val)')
  call self.setvar('&path',(add_dot ? '.,' : '').s:pathjoin([self.app().path()],path,old_path))
endfunction

function! s:BufSettings()
  if !exists('b:padrino_root')
    return ''
  endif
  let self = padrino#buffer()
  call s:SetBasePath()
  let rp = s:gsub(self.app().path(),'[ ,]','\\&')
  if stridx(&tags,rp.'/tmp/tags') == -1
    let &l:tags = rp . '/tmp/tags,' . &tags . ',' . rp . '/tags'
  endif
  if has("gui_win32") || has("gui_running")
    let code      = '*.rb;*.rake;Rakefile'
    let templates = '*.'.s:gsub(s:view_types,',',';*.')
    let fixtures  = '*.yml;*.csv'
    let statics   = '*.html;*.css;*.js;*.xml;*.xsd;*.sql;.htaccess;README;README_FOR_APP'
    let b:browsefilter = ""
          \."All Padrino Files\t".code.';'.templates.';'.fixtures.';'.statics."\n"
          \."Source Code (*.rb, *.rake)\t".code."\n"
          \."Templates (*.rhtml, *.rxml, *.rjs)\t".templates."\n"
          \."Fixtures (*.yml, *.csv)\t".fixtures."\n"
          \."Static Files (*.html, *.css, *.js)\t".statics."\n"
          \."All Files (*.*)\t*.*\n"
  endif
  call self.setvar('&includeexpr','PadrinoIncludeexpr()')
  call self.setvar('&suffixesadd', ".rb,.".s:gsub(s:view_types,',',',.').",.css,.js,.yml,.csv,.rake,.sql,.html,.xml")
  let ft = self.getvar('&filetype')
  if ft =~ '^\%(e\=ruby\|[yh]aml\|javascript\|css\|s[ac]ss\|lesscss\)$'
    call self.setvar('&shiftwidth',2)
    call self.setvar('&softtabstop',2)
    call self.setvar('&expandtab',1)
    if exists('+completefunc') && self.getvar('&completefunc') == ''
      call self.setvar('&completefunc','syntaxcomplete#Complete')
    endif
  endif
  if ft == 'ruby'
    call self.setvar('&suffixesadd',".rb,.".s:gsub(s:view_types,',',',.').",.yml,.csv,.rake,s.rb")
    call self.setvar('&define',self.define_pattern())
    " This really belongs in after/ftplugin/ruby.vim but we'll be nice
    if exists('g:loaded_surround') && self.getvar('surround_101') == ''
      call self.setvar('surround_5',   "\r\nend")
      call self.setvar('surround_69',  "\1expr: \1\rend")
      call self.setvar('surround_101', "\r\nend")
    endif
  elseif ft == 'yaml' || fnamemodify(self.name(),':e') == 'yml'
    call self.setvar('&define',self.define_pattern())
    call self.setvar('&suffixesadd',".yml,.csv,.rb,.".s:gsub(s:view_types,',',',.').",.rake,s.rb")
  elseif ft == 'eruby'
    call self.setvar('&suffixesadd',".".s:gsub(s:view_types,',',',.').",.rb,.css,.js,.html,.yml,.csv")
    if exists("g:loaded_allml")
      call self.setvar('allml_stylesheet_link_tag', "<%= stylesheet_link_tag '\r' %>")
      call self.setvar('allml_javascript_include_tag', "<%= javascript_include_tag '\r' %>")
      call self.setvar('allml_doctype_index', 10)
    endif
    if exists("g:loaded_ragtag")
      call self.setvar('ragtag_stylesheet_link_tag', "<%= stylesheet_link_tag '\r' %>")
      call self.setvar('ragtag_javascript_include_tag', "<%= javascript_include_tag '\r' %>")
      call self.setvar('ragtag_doctype_index', 10)
    endif
  elseif ft == 'haml'
    if exists("g:loaded_allml")
      call self.setvar('allml_stylesheet_link_tag', "= stylesheet_link_tag '\r'")
      call self.setvar('allml_javascript_include_tag', "= javascript_include_tag '\r'")
      call self.setvar('allml_doctype_index', 10)
    endif
    if exists("g:loaded_ragtag")
      call self.setvar('ragtag_stylesheet_link_tag', "= stylesheet_link_tag '\r'")
      call self.setvar('ragtag_javascript_include_tag', "= javascript_include_tag '\r'")
      call self.setvar('ragtag_doctype_index', 10)
    endif
  endif
  if ft == 'eruby' || ft == 'yaml'
    " surround.vim
    if exists("g:loaded_surround")
      " The idea behind the || part here is that one can normally define the
      " surrounding to omit the hyphen (since standard ERuby does not use it)
      " but have it added in Padrino ERuby files.  Unfortunately, this makes it
      " difficult if you really don't want a hyphen in Padrino ERuby files.  If
      " this is your desire, you will need to accomplish it via a padrino.vim
      " autocommand.
      if self.getvar('surround_45') == '' || self.getvar('surround_45') == "<% \r %>" " -
        call self.setvar('surround_45', "<% \r -%>")
      endif
      if self.getvar('surround_61') == '' " =
        call self.setvar('surround_61', "<%= \r %>")
      endif
      if self.getvar("surround_35") == '' " #
        call self.setvar('surround_35', "<%# \r %>")
      endif
      if self.getvar('surround_101') == '' || self.getvar('surround_101')== "<% \r %>\n<% end %>" "e
        call self.setvar('surround_5',   "<% \r -%>\n<% end -%>")
        call self.setvar('surround_69',  "<% \1expr: \1 -%>\r<% end -%>")
        call self.setvar('surround_101', "<% \r -%>\n<% end -%>")
      endif
    endif
  endif
endfunction

" }}}1
" Autocommands {{{1

augroup padrinoPluginAuto
  autocmd!
  autocmd User BufEnterPadrino call s:RefreshBuffer()
  autocmd User BufEnterPadrino call s:resetomnicomplete()
  autocmd User BufEnterPadrino call s:BufDatabase(-1)
  autocmd User dbextPreConnection call s:BufDatabase(1)
  autocmd BufWritePost */config/database.yml      call padrino#cache_clear("dbext_settings")
  autocmd BufWritePost */test/test_helper.rb      call padrino#cache_clear("user_assertions")
  autocmd BufWritePost */config/routes.rb         call padrino#cache_clear("named_routes")
  autocmd BufWritePost */config/environment.rb    call padrino#cache_clear("default_locale")
  autocmd BufWritePost */config/environments/*.rb call padrino#cache_clear("environments")
  autocmd BufWritePost */tasks/**.rake            call padrino#cache_clear("rake_tasks")
  autocmd BufWritePost */generators/**            call padrino#cache_clear("generators")
  autocmd FileType * if exists("b:padrino_root") | call s:BufSettings() | endif
  autocmd Syntax ruby,eruby,yaml,haml,javascript,coffee,padrinolog if exists("b:padrino_root") | call s:BufSyntax() | endif
  autocmd QuickFixCmdPre  make* call s:push_chdir()
  autocmd QuickFixCmdPost make* call s:pop_command()
augroup END

" }}}1
" Initialization {{{1

map <SID>xx <SID>xx
let s:sid = s:sub(maparg("<SID>xx"),'xx$','')
unmap <SID>xx
let s:file = expand('<sfile>:p')

if !exists('s:apps')
  let s:apps = {}
endif

" }}}1

let &cpo = s:cpo_save

" vim:set sw=2 sts=2:

