

function include_file(p)
  pth = site.templates .. "/" .. p
  f = io.open(pth, "r")
  print(f:read("*a"))
  f:close()
  return;
end


function dump_table(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

function make_list(dir, render_item) 
   p = child_pages(dir)
   for k,v in pairs(p) do
      print(render_item(p))
   end
end
