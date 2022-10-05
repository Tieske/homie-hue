local package_name = "homie-hue"
local package_version = "scm"
local rockspec_revision = "1"
local github_account_name = "Tieske"
local github_repo_name = "homie-hue"


package = package_name
version = package_version.."-"..rockspec_revision

source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = (package_version == "scm") and "main" or nil,
  tag = (package_version ~= "scm") and package_version or nil,
}

description = {
  summary = "Bridge to expose Philips Hue devices as Homie devices",
  detailed = [[
    Bridge to expose Philips Hue devices as Homie devices
  ]],
  license = "MIT",
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
}

dependencies = {
  "lua >= 5.1, < 5.5",
}

build = {
  type = "builtin",

  modules = {
    ["homie-hue.init"] = "src/homie-hue/init.lua",
  },

  copy_directories = {
    -- can be accessed by `luarocks homie-hue doc` from the commandline
    "docs",
  },
}
