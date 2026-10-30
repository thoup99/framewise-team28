--  Pair P / week 1: smoke tests for the initial proof targets.
--  These are regression tests, not a substitute for GNATprove.
with Ada.Command_Line;
with Ada.Text_IO;
with Framewise;
with Framewise.Timeline;

procedure P1_Foundation_Tests is
   use Ada.Text_IO;
   use Framewise;
   use Framewise.Timeline;

   S        : Sequence;
   Snapshot : Sequence;
   Ok       : Boolean;
   Failures : Natural := 0;

   procedure Check (Label_Text : String; Condition : Boolean);

   procedure Check (Label_Text : String; Condition : Boolean) is
   begin
      Put_Line ((if Condition then "PASS " else "FAIL ") & Label_Text);
      if not Condition then
         Failures := Failures + 1;
      end if;
   end Check;

begin
   Clear (S);
   Check ("Clear establishes Well_Formed", Well_Formed (S));
   Check ("Clear resets duration", Sequence_End (S) = 0);
   Check ("missing source", Find_Source (S, To_Name ("take1")) = No_Source);
   Check ("missing track", Find_Track (S, To_Name ("v1")) = 0);

   Add_Source (S, To_Name ("take1"), To_Path ("take1.mp4"),
               30 * Timebase, Video, Ok);
   Check ("Add_Source accepted", Ok and Well_Formed (S));
   Check ("Find_Source returns entry", Find_Source (S, To_Name ("take1")) = 1);
   Snapshot := S;
   Add_Source (S, To_Name ("take1"), To_Path ("other.mp4"),
               30 * Timebase, Video, Ok);
   Check ("duplicate source refuses atomically", not Ok and S = Snapshot);

   Add_Track (S, To_Name ("v1"), Video, Ok);
   Check ("Add_Track accepted", Ok and Well_Formed (S));
   Check ("Find_Track returns entry", Find_Track (S, To_Name ("v1")) = 1);
   Check ("new track has no duration", Track_End (S, 1) = 0
          and Sequence_End (S) = 0);
   Snapshot := S;
   Add_Track (S, To_Name ("v1"), Video, Ok);
   Check ("duplicate track refuses atomically", not Ok and S = Snapshot);

   Clear (S);
   Check ("Clear discards all sources/tracks",
          Well_Formed (S) and Find_Source (S, To_Name ("take1")) = No_Source
          and Find_Track (S, To_Name ("v1")) = 0);

   if Failures = 0 then
      Put_Line ("all P1 foundation tests passed");
   else
      Put_Line (Failures'Image & " P1 foundation test failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end P1_Foundation_Tests;
