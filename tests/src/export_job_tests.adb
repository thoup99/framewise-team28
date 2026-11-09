--  Exercise native polling and the Windows background-wait fallback, including
--  failures and reusing a finished job. Inputs come from check_shell_paths.py.
with Ada.Command_Line;
with Ada.Directories;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO;
with Framewise.Session;

procedure Export_Job_Tests is
   package FS renames Framewise.Session;
   S : FS.Session;
   Job : FS.Export_Job;
   R : FS.Response;
   Done : Boolean;

   procedure Execute (Line : String);
   procedure Await_Result;
   procedure Execute (Line : String) is
   begin
      FS.Execute (S, Line, R);
      pragma Assert (R.Ok, FS.Image (R));
   end Execute;

   procedure Await_Result is
      Deadline : constant Time := Clock + Seconds (30);
   begin
      loop
         FS.Poll_Export (Job, R, Done);
         exit when Done;
         pragma Assert (Clock < Deadline, "Export completion timed out");
         delay 0.01;
      end loop;
      pragma Assert (not FS.Export_Running (Job));
   end Await_Result;

   Prefix : constant String := Ada.Command_Line.Argument (2);
begin
   Execute ("settings 160 90 30");
   Execute ("import source " & FS.Quote_Path (Ada.Command_Line.Argument (1)) & " 0.4 video");
   Execute ("track v video");
   Execute ("place clip v source 0 0.4 0");
   for Background in Boolean loop
      declare
         Target : constant String := Prefix & (if Background then "_waiter.mp4" else "_native.mp4");
         History : constant Natural := FS.History_Length (S);
      begin
         FS.Start_Export (S, Target, Job, R, Wait_In_Background => Background);
         pragma Assert (R.Ok and then FS.Export_Running (Job), FS.Image (R));
         Await_Result;
         pragma Assert (R.Ok and then Ada.Directories.Exists (Target), FS.Image (R));
         FS.Start_Export (S, Prefix & "_missing/out.mp4", Job, R,
                          Wait_In_Background => Background);
         pragma Assert (R.Ok);
         Await_Result;
         pragma Assert (not R.Ok, "FFmpeg failure must be reported");
         pragma Assert ((for some C of FS.Image (R) => C = ASCII.LF),
                        "Failure must include captured FFmpeg diagnostics");
         --  A subsequent successful export proves the waiter was reclaimed.
         FS.Start_Export (S, Target, Job, R, Wait_In_Background => Background);
         pragma Assert (R.Ok);
         Await_Result;
         pragma Assert (R.Ok and then FS.History_Length (S) = History, FS.Image (R));
      end;
   end loop;
   Ada.Text_IO.Put_Line
     ("PASS: export completion, errors and retry with native and background waits");
end Export_Job_Tests;
