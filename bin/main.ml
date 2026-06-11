open CalendarLib
open Containers
open Fun

let parsedate d = CalendarLib.Printer.Date.from_fstring "%F" d
let today = Calendar.now ()

let () =
  print_endline "Supported hl langs:";
  Hilite.langs |> String.concat ", " |> print_endline;
  print_endline ""

type meta = {
  filename : string;
  name : string;
  date : Date.t option;
  content : unit -> [ `Text of string | `MDHtml of string | `Xml of string ];
  template : [ `Default | `Fname of string | `Rss ];
  extra_frontmatter : (string * string) list;
}

let lua_prelude = ref ""
let templates_dir = ref "templates"
let source_dir = ref "src"
let build_dir = ref "build"

let lua_push_table st m =
  let open Lua_api in
  Lua.newtable st;
  List.iter
    (fun (k, v) ->
      (match v with
      | `String v -> Lua.pushstring st v
      | `Int i -> Lua.pushinteger st i
      | `Bool i -> Lua.pushboolean st i);
      Lua.setfield st (-2) k)
    m;
  ()

let lua_push_array st m =
  let open Lua_api in
  Lua.newtable st;
  List.iteri
    (fun i push_fn ->
      Lua.pushinteger st (i + 1);
      push_fn st;
      Lua.settable st (-3))
    m;
  ()

module M = Map.Make (String)

type site_cfg = { url : string; title : string }

let lua_push_page_meta st cfg m =
  let d =
    Option.(
      map
        (Date.to_unixfloat %> Int.of_float %> fun x -> ("date", `Int x))
        m.date
      |> to_list)
  in
  let tbl_data =
    d
    @ [
        ("filename", `String m.filename);
        ("title", `String m.name);
        ( "url",
          `String
            (Filename.concat cfg.url (m.filename ^ ".html")
            |> Uri.of_string |> Uri.canonicalize |> Uri.to_string) );
      ]
    @ List.map (fun (k, v) -> ("fm_" ^ k, `String v)) m.extra_frontmatter
  in
  lua_push_table st tbl_data

let lua_push_site_meta st cfg =
  let site_data =
    [
      ("url", `String cfg.url);
      ("title", `String cfg.title);
      ("templates", `String !templates_dir);
    ]
  in
  lua_push_table st site_data

let body m =
  m.content () |> function `Text s -> s | `Xml s -> s | `MDHtml s -> s

let date m =
  Option.map (fun d -> CalendarLib.Printer.Date.sprint "%d %B %Y" d) m.date
  |> function
  | Some x -> x
  | None -> ""

let to_item cfg m =
  let pubdate : Ptime.t option =
    let d = m.date |> Option.map Date.to_unixfloat in
    Option.bind d Ptime.of_float_s
  in
  let link =
    Uri.canonicalize
    @@ Uri.of_string (Filename.concat cfg.url (m.filename ^ ".html"))
  in
  let guid = Rss.Guid_permalink link in
  Rss.item ~title:m.name ~data:body ?pubdate ~link ~guid ()

let gen_rss cfg (m : meta) (ms : meta list) =
  let default_date x =
    match x with Some d -> d | None -> parsedate "1970-01-01"
  in
  let link =
    Uri.canonicalize @@ Uri.of_string
    @@ Filename.concat cfg.url (m.filename ^ ".xml")
  in
  let met =
    ms
    |> List.filter (fun m -> not (Equal.poly m.template `Rss))
    |> List.sort (fun mi mj ->
        Calendar.Date.compare (default_date mi.date) (default_date mj.date))
    |> List.rev
    |> List.map (to_item cfg)
  in
  let now = today |> CalendarLib.Printer.Calendar.sprint "%c" in

  let channel = Rss.channel ~title:m.name ~desc:(body m) ~link met in
  let b = Buffer.create 1024 in
  let f = Format.formatter_of_buffer b in
  Rss.print_channel f channel;
  Buffer.to_bytes b |> Bytes.unsafe_to_string

let read_file ic = CCIO.read_all ic

let lua_register_printer st =
  let open Lua_api in
  let b = Buffer.create 1024 in
  let f s =
    let s = LuaL.checkstring st (-1) in
    Lua.pop st 1;
    Buffer.add_string b s;
    0
  in
  Lua.register st "print" f;
  b

let lua_register_page_content st meta =
  let open Lua_api in
  let f st =
    Lua.pushstring st (body meta);
    1
  in
  Lua.register st "page_content" f

let lua_register_cmarkit st =
  let open Lua_api in
  let f st =
    let text = LuaL.checkstring st (-1) in
    Lua.pop st 1;
    let l =
      Cmarkit.Doc.of_string ~heading_auto_ids:true ~strict:false text
      |> Hilite_markdown.transform |> Katex.cmarkit_map_katex
      |> Cmarkit_html.of_doc ~safe:false
    in
    Lua.pushstring st l;
    1
  in
  Lua.register st "render_markdown" f

let lua_register_texrender st =
  let ctx = lazy (Katex.create ()) in
  let open Lua_api in
  let f st =
    let text = LuaL.checkstring st (-1) in
    Lua.pop st 1;
    let l = Katex.eval_katex (Lazy.force ctx) text in
    let l = Result.get_or ~default:"error" l in
    Lua.pushstring st l;
    1
  in
  Lua.register st "render_math" f

let lua_register_metas_for_dir st cfg ms =
  let open Lua_api in
  let f st =
    let folder = LuaL.checkstring st (-1) in
    Lua.pop st 1;
    let met = M.find_opt folder ms in

    print_endline @@ "read dir dir" ^ folder;
    print_endline "pages";
    print_endline
      (M.to_list ms |> List.map (fun (k, _) -> k) |> String.concat ",");
    match met with
    | Some met ->
        let push_meta m st = lua_push_page_meta st cfg m in

        let default_date x =
          match x with Some d -> d | None -> parsedate "1970-01-01"
        in
        let met =
          met
          |> List.filter (fun m -> not (Equal.poly m.template `Rss))
          |> List.sort (fun mi mj ->
              Calendar.Date.compare (default_date mi.date)
                (default_date mj.date))
          |> List.rev
        in
        let values = List.map push_meta met in
        lua_push_array st values;
        1
    | _ ->
        Lua.pushstring st "error";
        1
  in
  Lua.register st "child_pages" f

let lua_register_glob st cfg =
  lua_register_cmarkit st;
  lua_register_texrender st;
  lua_push_site_meta st cfg;
  Lua_api.Lua.setglobal st "site"

let lua_block st cfg met metas inner_text =
  let open Lua_api in
  lua_push_page_meta st cfg met;
  Lua_api.Lua.setglobal st "page";
  lua_register_page_content st met;
  lua_register_metas_for_dir st cfg metas;
  let buf = lua_register_printer st in
  (if not @@ String.is_empty !lua_prelude then
     let r = LuaL.dofile st !lua_prelude in
     if not r then print_endline "WARN: error in lua prelude.");
  let r = LuaL.dostring st inner_text in
  if not r then
    print_endline ("WARN: Lua error in " ^ met.filename ^ ":" ^ inner_text);
  let s = Buffer.to_bytes buf |> Bytes.to_string in
  s

let luify cfg (temp : string) (met : meta) metas : string =
  let open Lua_api in
  let st = LuaL.newstate () in
  LuaL.openlibs st;
  lua_register_glob st cfg;
  let delim = Str.regexp {|%{\|\}%|} in
  let bgdeli = Str.regexp {|%\{|} in
  let n = Str.full_split delim temp in

  let buf = Buffer.create (String.length temp) in

  let rec unpack xs =
    match xs with
    | Str.Delim bg :: Str.Text inner_text :: rest
      when Str.string_match bgdeli bg 0 ->
        let s = lua_block st cfg met metas inner_text in
        Buffer.add_string buf s;
        unpack rest
    | Str.Text b :: rest ->
        Buffer.add_string buf b;
        unpack rest
    | [] -> ()
    | Str.Delim "}%" :: rest -> unpack rest
    | Str.Delim x :: _ -> failwith ("unexpec " ^ x)
  in
  unpack n;
  Buffer.to_bytes buf |> Bytes.unsafe_to_string

let extension s : string =
  Filename.extension s |> fun e ->
  Option.get_or ~default:e @@ String.chop_prefix ~pre:"." e

let lua_transform cfg met metas (doc : Cmarkit.Doc.t) =
  let open Lua_api in
  let st = LuaL.newstate () in
  LuaL.openlibs st;
  lua_register_glob st cfg;
  let block _mapper (b : Cmarkit.Block.t) =
    match b with
    | Cmarkit.Block.Code_block (node, meta) -> (
        let info =
          Cmarkit.Block.Code_block.info_string node |> Option.map fst
        in
        let code =
          Cmarkit.Block.Code_block.code node
          |> List.map Cmarkit.Block_line.to_string
          |> String.concat "\n"
        in
        match
          Option.bind info Cmarkit.Block.Code_block.language_of_info_string
        with
        | Some ("runlua", _) | Some ("evallua", _) ->
            let text = lua_block st cfg met metas code in
            let h = Cmarkit.Block_line.list_of_string text in
            `Map (Some (Cmarkit.Block.Html_block (h, meta)))
        | _ -> `Map (Some b))
    | _ -> `Default
  in
  let mapper = Cmarkit.Mapper.make ~block () in
  Cmarkit.Mapper.map_doc mapper doc

let drop_exn s : string =
  String.split_on_char '.' s |> List.rev |> List.tl |> List.rev
  |> String.concat "."

let parse_m cfg fs f =
  let ls = ref [] in
  let n = ref "" in
  while
    not
    @@ String.equal
         (n := input_line f;
          !n)
         "---"
  do
    ls := !n :: !ls
  done;
  let ls = !ls in
  let separate s =
    s
    |> String.map (function '\t' -> ' ' | o -> o)
    |> String.split_on_char ':'
    |> function
    | key :: values -> (String.trim key, String.trim (String.concat ":" values))
    | x -> failwith ("Bad " ^ String.concat " ^ " x)
  in
  let m = List.map separate ls |> M.of_list in
  let content = read_file f in
  close_in f;
  let filename = drop_exn fs in
  let template =
    M.find_opt "template" m |> function
    | Some "rss" -> `Rss
    | Some x -> `Fname x
    | None -> `Default
  in
  let extra_frontmatter =
    M.to_list m
    |> List.filter (function
      | "date", b -> false
      | "title", b -> false
      | _ -> true)
  in
  let m =
    {
      name = M.find "title" m;
      date = M.find_opt "date" m |> Option.map parsedate;
      content = (fun () -> `Text "");
      template;
      filename;
      extra_frontmatter;
    }
  in

  let do_md str =
    Cmarkit.Doc.of_string ~heading_auto_ids:true ~strict:false str
    |> Hilite_markdown.transform |> Katex.cmarkit_map_katex
    |> lua_transform cfg m M.empty
    |> Cmarkit_html.of_doc ~safe:false
  in
  let content () =
    match extension fs with
    | "md" -> `MDHtml (do_md content)
    | "markdown" -> `MDHtml (do_md content)
    | "html" -> `Xml content
    | _ -> `Text content
  in
  { m with content }

let build cfg fs =
  let f = open_in fs in
  let n = ref (input_line f) in
  let filename = fs in
  if String.equal !n "---" then parse_m cfg fs f
  else (
    (* Meta that encodes direct copy *)
    close_in f;
    let fs = Unix.realpath fs in
    let content _ =
      let f = open_in fs in
      let r = read_file f in
      close_in f;
      `Text r
    in
    {
      name = fs;
      filename;
      content;
      date = None;
      template = `Default;
      extra_frontmatter = [];
    })

let list_directory dir =
  if Sys.file_exists dir && Sys.is_directory dir then
    let file_array = Sys.readdir dir in
    file_array |> Array.to_list
    |> List.filter (fun f -> Sys.is_regular_file (Filename.concat dir f))
    (*|> List.filter (compose not (String.starts_with ~prefix:".")) *)
  else []

let load_templs dir =
  list_directory dir
  |> List.map (fun f ->
      let fn = Filename.concat dir f in
      let r = open_in fn in
      let t = read_file r in
      close_in r;
      (f, t))
  |> M.of_list

let rec list_directory_rec_build cfg dir : (string * meta list) list =
  print_endline ("dir " ^ dir);
  if Sys.file_exists dir && Sys.is_directory dir then (
    let file_array =
      Sys.readdir dir |> Array.to_list
      |> List.map (fun i -> Filename.concat dir i)
    in
    List.iter print_endline file_array;
    let files =
      file_array
      |> List.filter Sys.is_regular_file
      (*|> List.filter (compose not (String.starts_with ~prefix:".")) *)
      |> List.map (build cfg)
    in
    let dires = file_array |> List.filter Sys.is_directory in
    List.iter print_endline dires;
    let dirs =
      List.concat_map (fun d -> list_directory_rec_build cfg d) dires
    in
    (dir, files) :: dirs)
  else []

let rmdirrec odir =
  let files =
    CCIO.File.walk_l odir
    |> List.filter_map (function `File, e -> Some e | _ -> None)
  in
  files |> List.iter CCIO.File.remove_noerr

let process_dir cfg temps indir outdir =
  rmdirrec outdir;
  if not (Sys.file_exists outdir) then Sys.mkdir outdir 0o740;
  let cd = Sys.getcwd () in
  let temps = load_templs temps in
  M.iter (fun i _ -> print_endline ("template " ^ i)) temps;
  print_endline "";
  Sys.chdir indir;
  let built = list_directory_rec_build cfg "." in
  let bm = built |> M.of_list in
  print_endline "";
  print_endline "done build, outputting:";
  List.iter
    (fun (i, k) ->
      print_endline i;
      List.iter (fun x -> print_endline x.filename) k)
    built;
  let templated l =
    List.map
      (fun m ->
        let templ, fname =
          match m.template with
          | `Default -> (m.content (), m.filename)
          | `Fname f ->
              let t = M.find f temps in
              let s = luify cfg t m bm in
              (* run twice as hack for templated inclusions *)
              let s = luify cfg s m bm in
              (`Text s, m.filename ^ ".html")
          | `Rss ->
              let u = Filename.dirname m.filename in
              let s = gen_rss cfg m (M.find u bm) in
              (`Text s, m.filename ^ ".xml")
        in
        (m, fname, templ))
      l
  in
  Sys.chdir cd;
  Sys.chdir outdir;
  let writeout (d, ms) =
    if not (Sys.file_exists d) then Sys.mkdir d 0o740;
    templated ms
    |> List.iter (function m, fname, c ->
        let cont = match c with `Text t -> t | `Xml x -> x | `MDHtml x -> x in
        print_endline "output";
        print_endline fname;
        let os = open_out fname in
        output_string os cont;
        close_out os)
  in
  List.iter writeout built;
  Sys.chdir cd

let usage_msg = "sb [ optional args ]"

let serve ~config ~timeout (dir : string) addr port j : _ result =
  let module S = Tiny_httpd in
  let server = S.create ~max_connections:j ~addr ~port ~timeout () in
  let after_init () =
    Printf.printf "serve directory %s on http://%(%s%):%d\n%!" dir
      (if S.is_ipv6 server then "[%s]" else "%s")
      addr (S.port server)
  in
  Tiny_httpd.Dir.add_dir_path ~config ~dir ~prefix:"" server;
  S.run ~after_init server

let poll_dir dirs callback =
  let selectors =
    Inotify.[ S_Modify; S_Delete; S_Move; S_Create; S_Close_write ]
  in
  let p = Inotify.create () in
  dirs
  |> List.iter (fun dir ->
      CCIO.File.walk_l dir
      |> List.iter (function
        | `File, e -> ignore @@ Inotify.add_watch p e selectors
        | `Dir, d -> ignore @@ Inotify.add_watch p d selectors));
  let rec update () : unit =
    (* block until subscribed event *)
    let _ = Inotify.read p in
    let do_update = true in
    if do_update then callback ();
    update ()
  in
  update ()

let httpd site_cfg port () =
  let odir = Filename.temp_dir "preview" "d" in
  if not @@ CCIO.File.is_directory odir then Sys.mkdir odir 0o755;

  let config = Tiny_httpd.Dir.config ~dir_behavior:Index () in
  let addr = "127.0.0.1" in
  let port = port |> Int.of_string |> Option.get_exn_or "port not an int" in
  let url = Printf.sprintf "http://%s:%d" addr port in
  let callback =
   fun () -> process_dir { site_cfg with url } !templates_dir !source_dir odir
  in
  callback ();
  let timeout = 30. in
  let serve_thread =
    Thread.create
      (fun () ->
        serve ~config ~timeout odir addr port 2 |> function
        | Ok _ -> ()
        | Error e -> raise e)
      ()
  in
  let poll_thread =
    Thread.create
      (fun () -> poll_dir [ !source_dir; !templates_dir ] callback)
      ()
  in
  Thread.join serve_thread;
  Thread.join poll_thread;
  rmdirrec odir;
  ()

let () =
  let url = ref "http://localhost:8000/" in
  let site_title = ref "site title" in
  let preview = ref None in
  let speclist =
    [
      ( "-i",
        Arg.Set_string source_dir,
        "set input directory, default: " ^ !source_dir );
      ( "-o",
        Arg.Set_string build_dir,
        "set output directory, default: " ^ !build_dir );
      ( "--templates",
        Arg.Set_string templates_dir,
        "set templates directory, default: " ^ !templates_dir );
      ("--url", Arg.Set_string url, "set site public url, default: " ^ !url);
      ( "--prelude",
        Arg.Set_string lua_prelude,
        "prelude file for lua-based templater, default: nil" );
      ( "--preview",
        Arg.String (fun (u : string) -> preview := Some u),
        "port, live preview bind to port, default: nil" );
      ( "--title",
        Arg.Set_string site_title,
        "set site name title, default: " ^ !site_title );
    ]
  in
  Arg.parse speclist (fun f -> ()) usage_msg;

  if Sys.file_exists !templates_dir then
    templates_dir := Unix.realpath !templates_dir;
  if not @@ String.is_empty !lua_prelude then
    lua_prelude := Unix.realpath !lua_prelude;
  print_endline !lua_prelude;
  let cfg : site_cfg = { url = !url; title = !site_title } in
  !preview |> Option.iter (fun p -> httpd cfg p ());
  process_dir cfg !templates_dir !source_dir !build_dir
