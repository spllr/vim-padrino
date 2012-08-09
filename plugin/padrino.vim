" padrino.vim - Detect a padrino application
" Author:       Gerard Cahill
" License:	    This file is placed in the public domain.

" Install this file as plugin/padrino.vim.  See doc/padrino.txt for details. (Grab
" it from the URL above if you don't have it.)  To access it from Vim, see
" :help add-local-help (hint: :helptags ~/.vim/doc) Afterwards, you should be
" able to do :help padrino

if exists('g:loaded_padrino') || &cp || v:version < 700
  finish
endif
let g:loaded_padrino = 1

" Utility Functions {{{1

function! s:error(str)
  echohl ErrorMsg
  echomsg a:str
  echohl None
  let v:errmsg = a:str
endfunction

function! s:autoload(...)
  if !exists("g:autoloaded_padrino") && v:version >= 700
    runtime! autoload/padrino.vim
  endif
  if exists("g:autoloaded_padrino")
    if a:0
      exe a:1
    endif
    return 1
  endif
  if !exists("g:padrino_no_autoload_warning")
    let g:padrino_no_autoload_warning = 1
    if v:version >= 700
      call s:error("Disabling padrino.vim: autoload/padrino.vim is missing")
    else
      call s:error("Disabling padrino.vim: Vim version 7 or higher required")
    endif
  endif
  return ""
endfunction

" }}}1
" Configuration {{{

function! s:SetOptDefault(opt,val)
  if !exists("g:".a:opt)
    let g:{a:opt} = a:val
  endif
endfunction

call s:SetOptDefault("padrino_statusline",1)
call s:SetOptDefault("padrino_syntax",1)
call s:SetOptDefault("padrino_mappings",1)
call s:SetOptDefault("padrino_abbreviations",1)
call s:SetOptDefault("padrino_ctags_arguments","--languages=-javascript")
call s:SetOptDefault("padrino_default_file","README")
call s:SetOptDefault("padrino_root_url",'http://localhost:3000/')
call s:SetOptDefault("padrino_modelines",0)
call s:SetOptDefault("padrino_menu",!has('mac'))
call s:SetOptDefault("padrino_gnu_screen",1)
call s:SetOptDefault("padrino_history_size",5)
call s:SetOptDefault("padrino_generators","controller\ngenerator\nhelper\nintegration_test\nmailer\nmetal\nmigration\nmodel\nobserver\nperformance_test\nplugin\nresource\nscaffold\nscaffold_controller\nsession_migration\nstylesheets")
if exists("g:loaded_dbext") && executable("sqlite3") && ! executable("sqlite")
  " Since dbext can't find it by itself
  call s:SetOptDefault("dbext_default_SQLITE_bin","sqlite3")
endif

" }}}1
" Detection {{{1

function! s:escvar(r)
  let r = fnamemodify(a:r,':~')
  let r = substitute(r,'\W','\="_".char2nr(submatch(0))."_"','g')
  let r = substitute(r,'^\d','_&','')
  return r
endfunction

function! s:Detect(filename)
  let fn = substitute(fnamemodify(a:filename,":p"),'\c^file://','','')
  let sep = matchstr(fn,'^[^\\/]\{3,\}\zs[\\/]')
  if sep != ""
    let fn = getcwd().sep.fn
  endif
  if fn =~ '[\/]config[\/]apps\.rb$'
    return s:BufInit(strpart(fn,0,strlen(fn)-22))
  endif
  if isdirectory(fn)
    let fn = fnamemodify(fn,':s?[\/]$??')
  else
    let fn = fnamemodify(fn,':s?\(.*\)[\/][^\/]*$?\1?')
  endif
  let ofn = ""
  let nfn = fn
  while nfn != ofn && nfn != ""
    if exists("s:_".s:escvar(nfn))
      return s:BufInit(nfn)
    endif
    let ofn = nfn
    let nfn = fnamemodify(nfn,':h')
  endwhile
  let ofn = ""
  while fn != ofn
    if filereadable(fn . "/config/apps.rb")
      return s:BufInit(fn)
    endif
    let ofn = fn
    let fn = fnamemodify(ofn,':s?\(.*\)[\/]\(app\|config\|db\|doc\|features\|lib\|log\|models\|public\|script\|spec\|stories\|test\|tmp\|vendor\)\($\|[\/].*$\)?\1?')
  endwhile
  return 0
endfunction

function! s:BufInit(path)
  let s:_{s:escvar(a:path)} = 1
  if s:autoload()
    return PadrinoBufInit(a:path)
  endif
endfunction

" }}}1
" Initialization {{{1

augroup padrinoPluginDetect
  autocmd!
  autocmd BufNewFile,BufRead * call s:Detect(expand("<afile>:p"))
  autocmd VimEnter * if expand("<amatch>") == "" && !exists("b:padrino_root") | call s:Detect(getcwd()) | endif | if exists("b:padrino_root") | silent doau User BufEnterPadrino | endif
  autocmd FileType netrw if !exists("b:padrino_root") | call s:Detect(expand("<afile>:p")) | endif | if exists("b:padrino_root") | silent doau User BufEnterPadrino | endif
  autocmd BufEnter * if exists("b:padrino_root")|silent doau User BufEnterPadrino|endif
  autocmd BufLeave * if exists("b:padrino_root")|silent doau User BufLeavePadrino|endif
  autocmd Syntax padrinolog if s:autoload()|call padrino#log_syntax()|endif
augroup END

command! -bar -bang -nargs=* -complete=dir Padrino :if s:autoload()|call padrino#new_app_command(<bang>0,<f-args>)|endif

" }}}1
" abolish.vim support {{{1

function! s:function(name)
    return function(substitute(a:name,'^s:',matchstr(expand('<sfile>'), '<SNR>\d\+_'),''))
endfunction

augroup padrinoPluginAbolish
  autocmd!
  autocmd VimEnter * call s:abolish_setup()
augroup END

function! s:abolish_setup()
  if exists('g:Abolish') && has_key(g:Abolish,'Coercions')
    if !has_key(g:Abolish.Coercions,'l')
      let g:Abolish.Coercions.l = s:function('s:abolish_l')
    endif
    if !has_key(g:Abolish.Coercions,'t')
      let g:Abolish.Coercions.t = s:function('s:abolish_t')
    endif
  endif
endfunction

function! s:abolish_l(word)
  let singular = padrino#singularize(a:word)
  return a:word ==? singular ? padrino#pluralize(a:word) : singular
endfunction

function! s:abolish_t(word)
  if a:word =~# '\u'
    return padrino#pluralize(padrino#underscore(a:word))
  else
    return padrino#singularize(padrino#camelize(a:word))
  endif
endfunction

" }}}1
" Menus {{{1

if !(g:padrino_menu && has("menu"))
  finish
endif

function! s:sub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'')
endfunction

function! s:gsub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

function! s:menucmd(priority)
  return 'anoremenu <script> '.(exists("$CREAM") ? 87 : '').s:gsub(g:padrino_installed_menu,'[^.]','').'.'.a:priority.' '
endfunction

function! s:CreateMenus() abort
  if exists("g:padrino_installed_menu") && g:padrino_installed_menu != ""
    exe "aunmenu ".s:gsub(g:padrino_installed_menu,'\&','')
    unlet g:padrino_installed_menu
  endif
  if has("menu") && (exists("g:did_install_default_menus") || exists("$CREAM")) && g:padrino_menu
    if g:padrino_menu > 1
      let g:padrino_installed_menu = '&Padrino'
    else
      let g:padrino_installed_menu = '&Plugin.&Padrino'
    endif
    let dots = s:gsub(g:padrino_installed_menu,'[^.]','')
    let menucmd = s:menucmd(200)
    if exists("$CREAM")
      exe menucmd.g:padrino_installed_menu.'.-PSep- :'
      exe menucmd.g:padrino_installed_menu.'.&Related\ file\	:R\ /\ Alt+] :R<CR>'
      exe menucmd.g:padrino_installed_menu.'.&Alternate\ file\	:A\ /\ Alt+[ :A<CR>'
      exe menucmd.g:padrino_installed_menu.'.&File\ under\ cursor\	Ctrl+Enter :Rfind<CR>'
    else
      exe menucmd.g:padrino_installed_menu.'.-PSep- :'
      exe menucmd.g:padrino_installed_menu.'.&Related\ file\	:R\ /\ ]f :R<CR>'
      exe menucmd.g:padrino_installed_menu.'.&Alternate\ file\	:A\ /\ [f :A<CR>'
      exe menucmd.g:padrino_installed_menu.'.&File\ under\ cursor\	gf :Rfind<CR>'
    endif
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.Application\ &Controller :Rcontroller application<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.Application\ &Helper :Rhelper application<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.Application\ &Javascript :Rjavascript application<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.Application\ &Layout :Rlayout application<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.Application\ &README :R doc/README_FOR_APP<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.&Environment :Renvironment<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.&Database\ Configuration :R config/database.yml<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.Database\ &Schema :Rmigration 0<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.R&outes :Rinitializer<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Other\ files.&Test\ Helper :Rintegrationtest<CR>'
    exe menucmd.g:padrino_installed_menu.'.-FSep- :'
    exe menucmd.g:padrino_installed_menu.'.Ra&ke\	:Rake :Rake<CR>'
    let menucmd = substitute(menucmd,'200 $','500 ','')
    exe menucmd.g:padrino_installed_menu.'.&Server\	:Rserver.&Start\	:Rserver :Rserver<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Server\	:Rserver.&Force\ start\	:Rserver! :Rserver!<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Server\	:Rserver.&Kill\	:Rserver!\ - :Rserver! -<CR>'
    exe substitute(menucmd,'<script>','<script> <silent>','').g:padrino_installed_menu.'.&Evaluate\ Ruby\.\.\.\	:Rp :call <SID>menuprompt("Rp","Code to execute and output: ")<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Console\	:Rscript :Rscript console<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Preview\	:Rpreview :Rpreview<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Log\ file\	:Rlog :Rlog<CR>'
    exe substitute(s:sub(menucmd,'anoremenu','vnoremenu'),'<script>','<script> <silent>','').g:padrino_installed_menu.'.E&xtract\ as\ partial\	:Rextract :call <SID>menuprompt("'."'".'<,'."'".'>Rextract","Partial name (e.g., template or /controller/template): ")<CR>'
    exe menucmd.g:padrino_installed_menu.'.&Migration\ writer\	:Rinvert :Rinvert<CR>'
    exe menucmd.'         '.g:padrino_installed_menu.'.-HSep- :'
    exe substitute(menucmd,'<script>','<script> <silent>','').g:padrino_installed_menu.'.&Help\	:help\ padrino :if <SID>autoload()<Bar>exe PadrinoHelpCommand("")<Bar>endif<CR>'
    exe substitute(menucmd,'<script>','<script> <silent>','').g:padrino_installed_menu.'.Abo&ut\	 :if <SID>autoload()<Bar>exe PadrinoHelpCommand("about")<Bar>endif<CR>'
    let g:padrino_did_menus = 1
    call s:ProjectMenu()
    call s:menuBufLeave()
    if exists("b:padrino_root")
      call s:menuBufEnter()
    endif
  endif
endfunction

function! s:ProjectMenu()
  if exists("g:padrino_did_menus") && g:padrino_history_size > 0
    if !exists("g:PADRINO_HISTORY")
      let g:PADRINO_HISTORY = ""
    endif
    let history = g:PADRINO_HISTORY
    let menu = s:gsub(g:padrino_installed_menu,'\&','')
    silent! exe "aunmenu <script> ".menu.".Projects"
    let dots = s:gsub(menu,'[^.]','')
    exe 'anoremenu <script> <silent> '.(exists("$CREAM") ? '87' : '').dots.'.100 '.menu.'.Pro&jects.&New\.\.\.\	:Padrino :call <SID>menuprompt("Padrino","New application path and additional arguments: ")<CR>'
    exe 'anoremenu <script> '.menu.'.Pro&jects.-FSep- :'
    while history =~ '\n'
      let proj = matchstr(history,'^.\{-\}\ze\n')
      let history = s:sub(history,'^.{-}\n','')
      exe 'anoremenu <script> '.menu.'.Pro&jects.'.s:gsub(proj,'[.\\ ]','\\&').' :e '.s:gsub(proj."/".g:padrino_default_file,'[ !%#]','\\&')."<CR>"
    endwhile
  endif
endfunction

function! s:menuBufEnter()
  if exists("g:padrino_installed_menu") && g:padrino_installed_menu != ""
    let menu = s:gsub(g:padrino_installed_menu,'\&','')
    exe 'amenu enable '.menu.'.*'
    if PadrinoFileType() !~ '^view\>'
      exe 'vmenu disable '.menu.'.Extract\ as\ partial'
    endif
    if PadrinoFileType() !~ '^\%(db-\)\=migration$' || PadrinoFilePath() =~ '\<db/schema\.rb$'
      exe 'amenu disable '.menu.'.Migration\ writer'
    endif
    call s:ProjectMenu()
    silent! exe 'aunmenu       '.menu.'.Rake\ tasks'
    silent! exe 'aunmenu       '.menu.'.Generate'
    silent! exe 'aunmenu       '.menu.'.Destroy'
    if padrino#app().cache.needs('rake_tasks') || empty(padrino#app().rake_tasks())
      exe substitute(s:menucmd(300),'<script>','<script> <silent>','').g:padrino_installed_menu.'.Rake\ &tasks\	:Rake.Fill\ this\ menu :call padrino#app().rake_tasks()<Bar>call <SID>menuBufLeave()<Bar>call <SID>menuBufEnter()<CR>'
    else
      let i = 0
      while i < len(padrino#app().rake_tasks())
        let task = padrino#app().rake_tasks()[i]
        exe s:menucmd(300).g:padrino_installed_menu.'.Rake\ &tasks\	:Rake.'.s:sub(task,':',':.').' :Rake '.task.'<CR>'
        let i += 1
      endwhile
    endif
    let i = 0
    let menucmd = substitute(s:menucmd(400),'<script>','<script> <silent>','').g:padrino_installed_menu
    while i < len(padrino#app().generators())
      let generator = padrino#app().generators()[i]
      exe menucmd.'.&Generate\	:Rgen.'.s:gsub(generator,'_','\\ ').' :call <SID>menuprompt("Rgenerate '.generator.'","Arguments for script/generate '.generator.': ")<CR>'
      exe menucmd.'.&Destroy\	:Rdestroy.'.s:gsub(generator,'_','\\ ').' :call <SID>menuprompt("Rdestroy '.generator.'","Arguments for script/destroy '.generator.': ")<CR>'
      let i += 1
    endwhile
  endif
endfunction

function! s:menuBufLeave()
  if exists("g:padrino_installed_menu") && g:padrino_installed_menu != ""
    let menu = s:gsub(g:padrino_installed_menu,'\&','')
    exe 'amenu disable '.menu.'.*'
    exe 'amenu enable  '.menu.'.Help\	'
    exe 'amenu enable  '.menu.'.About\	'
    exe 'amenu enable  '.menu.'.Projects'
    silent! exe 'aunmenu       '.menu.'.Rake\ tasks'
    silent! exe 'aunmenu       '.menu.'.Generate'
    silent! exe 'aunmenu       '.menu.'.Destroy'
    exe s:menucmd(300).g:padrino_installed_menu.'.Rake\ tasks\	:Rake.-TSep- :'
    exe s:menucmd(400).g:padrino_installed_menu.'.&Generate\	:Rgen.-GSep- :'
    exe s:menucmd(400).g:padrino_installed_menu.'.&Destroy\	:Rdestroy.-DSep- :'
  endif
endfunction

function! s:menuprompt(vimcmd,prompt)
  let res = inputdialog(a:prompt,'','!!!')
  if res == '!!!'
    return ""
  endif
  exe a:vimcmd." ".res
endfunction

call s:CreateMenus()

augroup padrinoPluginMenu
  autocmd!
  autocmd User BufEnterPadrino call s:menuBufEnter()
  autocmd User BufLeavePadrino call s:menuBufLeave()
  " g:PADRINO_HISTORY hasn't been set when s:InitPlugin() is called.
  autocmd VimEnter *         call s:ProjectMenu()
augroup END

" }}}1
" vim:set sw=2 sts=2:

