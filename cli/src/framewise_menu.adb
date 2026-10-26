--  framewise_menu: a simple numbered menu over the Framewise session.  
--
--     framewise_menu
--
--  Like framewise_cli, this program has no editing logic of its own.
--  Each menu item asks a few questions, builds one command line (for
--  example "split c1 4 c1b"), prints it, and hands it to
--  Framewise.Session.Execute. The reply ("ok ..." or "err ...") is
--  printed as is. The menu is a script generator: everything it does,
--  a .fw file can do.
--
--  Two items live in the menu, not in the session:
--    * Create new project: throws away the session, starts an empty one.
--    * Redo: the session has undo only. Before an undo, the menu reads
--      the last history line (History_Line) and keeps it. Redo sends
--      that line again. Any new edit clears the redo list.

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings;           use Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Framewise.Session;

procedure Framewise_Menu is
   package FS renames Framewise.Session;

   type Line_Array is array (1 .. FS.Max_History) of Unbounded_String;

   R : FS.Response;

   --  Ask a question, return the trimmed answer.
   function Ask (Prompt : String) return String is
   begin
      Put (Prompt & ": ");
      return Trim (Get_Line, Both);
   end Ask;

   --  " WORD" when the answer is not empty, "" otherwise.
   --  Used for optional arguments such as [video|audio|both].
   function Opt (Answer : String) return String is
   begin
      if Answer = "" then
         return "";
      else
         return " " & Answer;
      end if;
   end Opt;

   --  Show the command line, send it to the session, show the reply.
   procedure Run (S : in out FS.Session; Line : String) is
   begin
      Put_Line ("  > " & Line);
      FS.Execute (S, Line, R);
      Put_Line ("  " & FS.Image (R));
   end Run;

   procedure Print_Menu is
   begin
      New_Line;
      Put_Line ("============ FRAMEWISE ============");
      Put_Line ("  1. Create new project");
      Put_Line ("  2. Render settings");
      Put_Line ("  3. Import a source");
      Put_Line ("  4. Add a track");
      Put_Line ("  5. Place a clip");
      Put_Line ("  6. Move a clip");
      Put_Line ("  7. Trim a clip");
      Put_Line ("  8. Split a clip");
      Put_Line ("  9. Delete a clip");
      Put_Line (" 10. Undo");
      Put_Line (" 11. Redo");
      Put_Line (" 12. List timeline");
      Put_Line (" 13. Info (clip, track or source)");
      Put_Line (" 14. Save project (.fw)");
      Put_Line (" 15. Load project (.fw)");
      Put_Line (" 16. Show ffmpeg plan");
      Put_Line ("  0. Quit");
      Put_Line ("===================================");
      Put_Line ("Times are in seconds, e.g. 4 or 8.5");
   end Print_Menu;

   function Read_Choice return Integer is
   begin
      return Integer'Value (Ask ("Choose an option"));
   exception
      when Constraint_Error =>
         return -1;
   end Read_Choice;

   Choice : Integer;
   Quit   : Boolean := False;

begin
   --  Each pass of Projects starts with a fresh, empty session.
   --  "Create new project" leaves the inner loop to get a new one.
   Projects :
   loop
      declare
         S          : FS.Session;
         Redo_Lines : Line_Array;
         Redo_Count : Natural := 0;

         --  For editing commands: run the line, and if it added to the
         --  history (a successful edit), the redo list no longer applies.
         procedure Edit (Line : String) is
            Before : constant Natural := FS.History_Length (S);
         begin
            Run (S, Line);
            if FS.History_Length (S) > Before then
               Redo_Count := 0;
            end if;
         end Edit;

         procedure Do_Undo is
            Last : Unbounded_String;
         begin
            if FS.History_Length (S) > 0 then
               Last := To_Unbounded_String
                 (FS.History_Line (S, FS.History_Length (S)));
            end if;
            Run (S, "undo");
            if R.Ok and then Redo_Count < Redo_Lines'Last then
               Redo_Count := Redo_Count + 1;
               Redo_Lines (Redo_Count) := Last;
            end if;
         end Do_Undo;

         procedure Do_Redo is
         begin
            if Redo_Count = 0 then
               Put_Line ("  err nothing to redo");
               return;
            end if;
            Run (S, To_String (Redo_Lines (Redo_Count)));
            if R.Ok then
               Redo_Count := Redo_Count - 1;
            end if;
         end Do_Redo;

      begin
         Menu :
         loop
            Print_Menu;
            Choice := Read_Choice;
            New_Line;

            case Choice is
               when 1 =>
                  if Ask ("Start a new empty project? Unsaved changes are lost (y/n)")
                    = "y"
                  then
                     Put_Line ("  ok new empty project");
                     exit Menu;
                  else
                     Put_Line ("  Cancelled.");
                  end if;

               when 2 =>
                  declare
                     W   : constant String := Ask ("Width (e.g. 1280)");
                     H   : constant String := Ask ("Height (e.g. 720)");
                     FPS : constant String := Ask ("Frames per second (e.g. 30)");
                  begin
                     Edit ("settings " & W & " " & H & " " & FPS);
                  end;

               when 3 =>
                  declare
                     N    : constant String := Ask ("Source name (e.g. take1)");
                     F    : constant String := Ask ("File (e.g. take1.mp4)");
                     Len  : constant String := Ask ("Length in seconds");
                     Kind : constant String := Ask ("Kind video/audio/both (blank = both)");
                  begin
                     Edit ("import " & N & " " & F & " " & Len & Opt (Kind));
                  end;

               when 4 =>
                  declare
                     N    : constant String := Ask ("Track name (e.g. v1)");
                     Kind : constant String := Ask ("Kind video/audio/both (blank = video)");
                  begin
                     Edit ("track " & N & Opt (Kind));
                  end;

               when 5 =>
                  declare
                     C     : constant String := Ask ("New clip name (e.g. c1)");
                     T     : constant String := Ask ("On track");
                     Src   : constant String := Ask ("From source");
                     In_T  : constant String := Ask ("Source in (seconds)");
                     Out_T : constant String := Ask ("Source out (seconds)");
                     At_T  : constant String := Ask ("Place at timeline time (seconds)");
                  begin
                     Edit ("place " & C & " " & T & " " & Src & " "
                           & In_T & " " & Out_T & " " & At_T);
                  end;

               when 6 =>
                  declare
                     C    : constant String := Ask ("Clip name");
                     To_T : constant String := Ask ("Move to timeline time (seconds)");
                  begin
                     Edit ("move " & C & " " & To_T);
                  end;

               when 7 =>
                  declare
                     C     : constant String := Ask ("Clip name");
                     In_T  : constant String := Ask ("New source in (seconds)");
                     Out_T : constant String := Ask ("New source out (seconds)");
                  begin
                     Edit ("trim " & C & " " & In_T & " " & Out_T);
                  end;

               when 8 =>
                  declare
                     C     : constant String := Ask ("Clip name");
                     At_T  : constant String := Ask ("Cut at timeline time (seconds)");
                     Right : constant String := Ask ("Name for the right part");
                  begin
                     Edit ("split " & C & " " & At_T & " " & Right);
                  end;

               when 9 =>
                  Edit ("delete " & Ask ("Clip name"));

               when 10 =>
                  Do_Undo;

               when 11 =>
                  Do_Redo;

               when 12 =>
                  Run (S, "list");

               when 13 =>
                  Run (S, "info " & Ask ("Clip, track or source name"));

               when 14 =>
                  Run (S, "save " & Ask ("File (e.g. demo.fw)"));

               when 15 =>
                  Run (S, "load " & Ask ("File (e.g. ../examples/cut.fw)"));
                  Redo_Count := 0;   --  a loaded project starts a new history

               when 16 =>
                  Run (S, "plan " & Ask ("Output file (e.g. out.mp4)"));

               when 0 =>
                  Quit := True;
                  exit Menu;

               when others =>
                  Put_Line ("Unknown option.");
            end case;
         end loop Menu;
      end;

      exit Projects when Quit;
   end loop Projects;

   Put_Line ("Goodbye.");

exception
   when End_Error =>
      New_Line;
      Put_Line ("Goodbye.");
end Framewise_Menu;