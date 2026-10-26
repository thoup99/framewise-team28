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

with Ada.Text_IO;       use Ada.Text_IO;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Framewise.Session;

procedure Framewise_Menu is
   package FS renames Framewise.Session;

   S : FS.Session;
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
   procedure Run (Line : String) is
   begin
      Put_Line ("  > " & Line);
      FS.Execute (S, Line, R);
      Put_Line ("  " & FS.Image (R));
   end Run;

   procedure Print_Menu is
   begin
      New_Line;
      Put_Line ("============ FRAMEWISE ============");
      Put_Line ("  1. Render settings");
      Put_Line ("  2. Import a source");
      Put_Line ("  3. Add a track");
      Put_Line ("  4. Place a clip");
      Put_Line ("  5. Move a clip");
      Put_Line ("  6. Trim a clip");
      Put_Line ("  7. Split a clip");
      Put_Line ("  8. Delete a clip");
      Put_Line ("  9. Undo");
      Put_Line (" 10. List timeline");
      Put_Line (" 11. Info (clip, track or source)");
      Put_Line (" 12. Save project (.fw)");
      Put_Line (" 13. Load project (.fw)");
      Put_Line (" 14. Show ffmpeg plan");
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

begin
   loop
      Print_Menu;
      Choice := Read_Choice;
      New_Line;

      case Choice is
         when 1 =>
            declare
               W   : constant String := Ask ("Width (e.g. 1280)");
               H   : constant String := Ask ("Height (e.g. 720)");
               FPS : constant String := Ask ("Frames per second (e.g. 30)");
            begin
               Run ("settings " & W & " " & H & " " & FPS);
            end;

         when 2 =>
            declare
               N    : constant String := Ask ("Source name (e.g. take1)");
               F    : constant String := Ask ("File (e.g. take1.mp4)");
               Len  : constant String := Ask ("Length in seconds");
               Kind : constant String := Ask ("Kind video/audio/both (blank = both)");
            begin
               Run ("import " & N & " " & F & " " & Len & Opt (Kind));
            end;

         when 3 =>
            declare
               N    : constant String := Ask ("Track name (e.g. v1)");
               Kind : constant String := Ask ("Kind video/audio/both (blank = video)");
            begin
               Run ("track " & N & Opt (Kind));
            end;

         when 4 =>
            declare
               C     : constant String := Ask ("New clip name (e.g. c1)");
               T     : constant String := Ask ("On track");
               Src   : constant String := Ask ("From source");
               In_T  : constant String := Ask ("Source in (seconds)");
               Out_T : constant String := Ask ("Source out (seconds)");
               At_T  : constant String := Ask ("Place at timeline time (seconds)");
            begin
               Run ("place " & C & " " & T & " " & Src & " "
                    & In_T & " " & Out_T & " " & At_T);
            end;

         when 5 =>
            declare
               C    : constant String := Ask ("Clip name");
               To_T : constant String := Ask ("Move to timeline time (seconds)");
            begin
               Run ("move " & C & " " & To_T);
            end;

         when 6 =>
            declare
               C     : constant String := Ask ("Clip name");
               In_T  : constant String := Ask ("New source in (seconds)");
               Out_T : constant String := Ask ("New source out (seconds)");
            begin
               Run ("trim " & C & " " & In_T & " " & Out_T);
            end;

         when 7 =>
            declare
               C     : constant String := Ask ("Clip name");
               At_T  : constant String := Ask ("Cut at timeline time (seconds)");
               Right : constant String := Ask ("Name for the right part");
            begin
               Run ("split " & C & " " & At_T & " " & Right);
            end;

         when 8 =>
            Run ("delete " & Ask ("Clip name"));

         when 9 =>
            Run ("undo");

         when 10 =>
            Run ("list");

         when 11 =>
            Run ("info " & Ask ("Clip, track or source name"));

         when 12 =>
            Run ("save " & Ask ("File (e.g. demo.fw)"));

         when 13 =>
            Run ("load " & Ask ("File (e.g. ../examples/cut.fw)"));

         when 14 =>
            Run ("plan " & Ask ("Output file (e.g. out.mp4)"));

         when 0 =>
            exit;

         when others =>
            Put_Line ("Unknown option.");
      end case;
   end loop;

   Put_Line ("Goodbye.");

exception
   when End_Error =>
      New_Line;
      Put_Line ("Goodbye.");
end Framewise_Menu;
