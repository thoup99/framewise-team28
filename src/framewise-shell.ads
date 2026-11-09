--  Native shell selection and path quoting shared by export and proxy jobs.
with GNAT.OS_Lib;

package Framewise.Shell is
   Is_Windows : constant Boolean := GNAT.OS_Lib.Directory_Separator = '\';

   function Executable (Windows : Boolean := Is_Windows) return String is
     (if Windows then "cmd.exe" else "sh");

   function Quote_Path (Path : String; Windows : Boolean := Is_Windows) return String;
   --  Quote one filename, preserving backslashes and shell metacharacters.
   --  Windows filenames cannot contain double quotes.

   procedure Run (Command : String; Status : out Integer; Found : out Boolean);
   --  Use only the host's native shell, regardless of other shells on PATH.
end Framewise.Shell;
