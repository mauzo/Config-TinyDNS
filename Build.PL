use Module::Build;

Module::Build->new(
    module_name     => "Config::TinyDNS",
    license         => "bsd",
    requires        => {
        "File::Slurp"       => 0,
        "Exporter::NoWork"  => 0,
    },
    build_requires  => {
        "Test::More"        => "0.65",
    },
)->create_build_script;
