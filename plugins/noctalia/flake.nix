{
  description = "Noctalia Independent Plugin Registry";
  
  inputs = {
    # NOCTALIA MAIN
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
    };
  };

  outputs = inputs: {
    noctalia-main = inputs.noctalia;
  };
}
