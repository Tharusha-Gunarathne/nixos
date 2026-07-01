{
  description = "Pinned sources for Claude Code skills";

  inputs = {
    caveman-skill = {
      url = "github:JuliusBrussee/caveman";
      flake = false;
    };
    taste-skill = {
      url = "github:Leonxlnx/taste-skill";
      flake = false;
    };
    hallmark-skill = {
      url = "github:nutlope/hallmark";
      flake = false;
    };
  };

  # inputs.claude-plugins.inputs.<name> for each pinned source.
  outputs = inputs: {inherit inputs;};
}
