with Ada.Strings.Unbounded;

package body Framewise.Shell is
   function Arguments (Command : String) return GNAT.OS_Lib.Argument_List_Access;

   function Quote_Path (Path : String; Windows : Boolean := Is_Windows) return String is
      use Ada.Strings.Unbounded;
      Result : Unbounded_String := To_Unbounded_String ("'");
   begin
      if Windows then
         return '"' & Path & '"';
      end if;
      --  POSIX single quotes keep backslashes, dollars and other shell syntax
      --  literal. An apostrophe needs to be emitted outside the quoted span.
      for C of Path loop
         if C = ''' then
            Append (Result, "'\''");
         else
            Append (Result, C);
         end if;
      end loop;
      Append (Result, ''');
      return To_String (Result);
   end Quote_Path;

   function Arguments (Command : String) return GNAT.OS_Lib.Argument_List_Access is
      use GNAT.OS_Lib;
      Args : Argument_List_Access;
   begin
      if Is_Windows then
         --  Ignore cmd AutoRun hooks and disable delayed expansion so an
         --  exclamation mark in a quoted filename stays literal.
         --  Wrap the whole /C payload before Spawn. GNAT otherwise applies
         --  C-runtime escaping to its inner quotes, which cmd does not use.
         --  /S strips only this outer pair and preserves quoted filenames.
         Args := new Argument_List'
           (new String'("/D"), new String'("/V:OFF"), new String'("/S"),
            new String'("/C"), new String'('"' & Command & '"'));
      else
         Args := new Argument_List'(new String'("-c"), new String'(Command));
      end if;
      return Args;
   end Arguments;

   function Start
     (Command : String; Output : GNAT.OS_Lib.File_Descriptor) return GNAT.OS_Lib.Process_Id
   is
      use GNAT.OS_Lib;
      Program : GNAT.OS_Lib.String_Access := Locate_Exec_On_Path (Executable);
      Args : Argument_List_Access;
      PID : Process_Id;
   begin
      if Program = null then
         return Invalid_Pid;
      end if;
      Args := Arguments (Command);
      PID := Non_Blocking_Spawn (Program.all, Args.all, Output, Err_To_Out => True);
      Free (Args);
      Free (Program);
      return PID;
   end Start;

   procedure Run (Command : String; Status : out Integer; Found : out Boolean) is
      use GNAT.OS_Lib;
      Program : GNAT.OS_Lib.String_Access := Locate_Exec_On_Path (Executable);
      Args : Argument_List_Access;
   begin
      Status := -1;
      Found := Program /= null;
      if not Found then
         return;
      end if;
      Args := Arguments (Command);
      Status := Spawn (Program.all, Args.all);
      Free (Args);
      Free (Program);
   end Run;
end Framewise.Shell;
