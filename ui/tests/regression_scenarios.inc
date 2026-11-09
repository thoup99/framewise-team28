      --  Test-only replacement for A.Run. Runs against the real editor,
      --  callback procedures, widgets and SDL window created above.
      declare
         Test_Dir : constant String := Ada.Environment_Variables.Value ("FRAMEWISE_TEST_DIR");
         Initial_History : US.Unbounded_String;
         Clip_Name : US.Unbounded_String;
         function Native_Title (Window : Adi.SDL.Video.SDL_Window_Ptr)
           return Interfaces.C.Strings.chars_ptr
           with Import, Convention => C, External_Name => "SDL_GetWindowTitle";

         procedure Check (Condition : Boolean; Message : String) is
         begin
            if not Condition then
               raise Program_Error with Message;
            end if;
         end Check;

         procedure Check_Editor_Log (Line : String; Expected : Natural := 1) is
         begin
            Check (Ada.Strings.Fixed.Count (Adi.Widget.Text_Editor.Get_Text (Console_Output),
              "[Editor] " & Line & Ada.Characters.Latin_1.LF) = Expected,
              "Editor log count for " & Line);
         end Check_Editor_Log;

         procedure Stage (Name : String) is
         begin
            Ada.Text_IO.Put_Line ("CHECK: " & Name);
         end Stage;

         function Files (Path : String) return Adi.OS.String_Array is
           ([US.To_Unbounded_String (Path)]);

         procedure Apply is
         begin
            Form_Result (Null_Handle, 1, "Apply");
         end Apply;

         procedure Assert_Centered is
            L : constant Rectangle := Get_Geometry (+Start_Button);
            R : constant Rectangle := Get_Geometry (+End_Button);
            P : constant Rectangle := Get_Geometry (+Preview);
         begin
            Check (abs ((L.X + R.X + R.Width) / 2.0 - (P.X + P.Width / 2.0)) < 1.0,
                   "Playback controls must remain centered under preview");
         end Assert_Centered;
      begin
         Stage ("startup, playback layout and timeline selector order");
         Render (W);
         Check (Interfaces.C.Strings.Value (Native_Title (Get_SDL_Window (W))) = "Framewise",
                "Untitled window title");
         Check (Current_Filter = All_Media, "All must be the default filter");
         Check (Has_State (+Filter_Buttons (All_Media), State_Selected), "All filter highlight");
         Check (Has_State (+Play_Button, State_Disabled), "Playback must remain unavailable");
         Check (Get_Child_Handle (+Placement_Row, 2) = Widget_Handle'(+Source_Choice),
                "Media selector must precede target track");
         Check (Get_Child_Handle (+Placement_Row, 4) = Widget_Handle'(+Track_Choice),
                "Track selector order");
         Check (Get_Child_Handle (+Placement_Row, 5) = Widget_Handle'(+Place_Button),
                "Place button order");
         Assert_Centered;
         Check (Get_Scroll_Max_Offset_Y (+Track_Scroll) = 0.0, "Empty timeline must not overflow");

         Stage ("File menu clears a previously selected row when reopened");
         Clicked (+File_Button);
         Render (W);
         declare
            Popup : constant Widget_Handle := Get_Overlay_Handle (W, Overlay_Count (W));
            Row : constant Widget_Handle := Get_Child_Handle (Popup, 6);
            G : constant Rectangle := Geometry_In_Window (Row);
         begin
            Adi.Window.On_Mouse_Down (W, G.X + 10.0, G.Y + G.Height / 2.0, Left_Button);
            Adi.Window.On_Mouse_Up (W, G.X + 10.0, G.Y + G.Height / 2.0, Left_Button);
            Check (Dialogs.Is_Shown (Form), "Selected File menu action opens its dialog");
         end;
         Form_Result (Null_Handle, 2, "Cancel");
         Clicked (+File_Button);
         Render (W);
         declare
            Popup : constant Widget_Handle := Get_Overlay_Handle (W, Overlay_Count (W));
            Row : constant Widget_Handle := Get_Child_Handle (Popup, 6);
            G : constant Rectangle := Geometry_In_Window (Row);
         begin
            Check (not Has_State (Row, State_Selected), "Reopened File menu has no sticky selected row");
            Adi.Window.On_Mouse_Move (W, G.X + 10.0, G.Y + G.Height / 2.0);
            Render (W);
            Check (Get_Resolved_Part_Style (Row, Main_Part).Background_Color = RGB (45, 78, 119),
                   "File menu action highlights on hover");
            Adi.Window.On_Mouse_Move (W, G.X + G.Width + 20.0, G.Y);
            Render (W);
            Check (not Has_State (Row, State_Hovered) and then not Has_State (Row, State_Selected),
                   "Menu highlight clears after pointer leaves");
            Check (Get_Resolved_Part_Style (Row, Main_Part).Background_Color /= RGB (45, 78, 119),
                   "No persistent highlight remains after hover");
         end;
         Menus.Hide (File_Menu);

         Stage ("snap interval field placement, typing and validation");
         declare
            V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
            Before : constant String := Adi.Widget.Text_Editor.Get_Text (Console_Output);
            Saved : constant US.Unbounded_String := History;
            procedure Enter_Interval (Text : String) is
            begin
               Set_Focus (W, +Snap_Interval_Input);
               Adi.Window.On_Key_Down
                 (W, Adi.SDL.Events.SDL_SCANCODE_A, 0, Adi.SDL.Events.SDL_KMOD_CTRL, False);
               Adi.Window.On_Key_Down (W, Adi.SDL.Events.SDL_SCANCODE_BACKSPACE, 0, 0, False);
               if Text'Length > 0 then
                  Adi.Window.On_Text_Input (W, Text);
               end if;
            end Enter_Interval;
         begin
            Check (Get_Child_Handle (+Timeline_Tools, 9) = Widget_Handle'(+Scroll_Right),
                   "Later remains the last navigation button");
            Check (Get_Child_Handle (+Timeline_Tools, 11) = Widget_Handle'(+Snap_Interval_Input),
                   "Snap input follows Later and its label");
            Check (Inputs.Get_Text (Snap_Interval_Input) = "0.5" and then
              V.Snap_Interval = Framewise.Timebase / 2, "Default snap interval is half a second");
            Check (not Is_Visible (+Tool_Status) and then Labels.Get_Text (Tool_Status) = "",
                   "Select instruction text is removed");
            Enter_Interval ("0.25");
            Check (V.Snap_Interval = Framewise.Timebase / 4, "Typed quarter-second interval reaches timeline");
            Render (W);
            declare
               Caret : Boolean := False;
            begin
               for I in 1 .. Item_Count (+Snap_Interval_Input) loop
                  declare
                     Drawn : constant Item := Get_Item (+Snap_Interval_Input, I);
                  begin
                     Caret := Caret or else (Drawn.Part = Cursor_Part and then
                       Drawn.Geometry.Width > 0.0 and then Drawn.Geometry.Height > 0.0);
                  end;
               end loop;
               Check (Caret, "Snap interval input has a visible typing caret");
            end;
            Enter_Interval ("0");
            Check (V.Snap_Interval = Framewise.Timebase / 4, "Zero retains last valid interval");
            Enter_Interval ("-1");
            Check (V.Snap_Interval = Framewise.Timebase / 4, "Negative interval rejected");
            Enter_Interval ("abc");
            Check (V.Snap_Interval = Framewise.Timebase / 4, "Nonnumeric interval rejected");
            Enter_Interval ("1e100");
            Check (V.Snap_Interval = Framewise.Timebase / 4, "Oversized interval rejected");
            Enter_Interval ("0.000001");
            Check (V.Snap_Interval = Framewise.Timebase / 4, "Sub-tick interval rejected");
            Enter_Interval ("");
            Check (V.Snap_Interval = Framewise.Timebase / 4, "Empty input retains last valid interval");
            Render (W);
            Check (Get_Resolved_Part_Style (+Snap_Interval_Input, Text_Part).Color = RGB (255, 150, 150),
                   "Invalid input is visibly marked");
            Enter_Interval ("1");
            Check (V.Snap_Interval = Framewise.Timebase, "Whole-second interval accepted");
            Enter_Interval ("0.1");
            Check (V.Snap_Interval = Framewise.Timebase / 10, "Decimal interval stored as exact ticks");
            Adi.Window.On_Key_Down
              (W, Adi.SDL.Events.SDL_SCANCODE_Z, 0, Adi.SDL.Events.SDL_KMOD_CTRL, False);
            Check (History = Saved and then not Dirty and then
              Adi.Widget.Text_Editor.Get_Text (Console_Output) = Before,
              "Editing snap settings and undoing text must not execute project commands");
            Enter_Interval ("0.5");
            Render (W);
            Check (Get_Resolved_Part_Style (+Snap_Interval_Input, Text_Part).Color = RGB (215, 225, 239),
                   "Valid input restores normal text color");
            Set_Focus (W, +Tracks);
         end;

         Stage ("button validation failures reach the closed console");
         Initial_History := History;
         Clicked (+Delete_Button);
         Check_Editor_Log ("Delete Clip");
         Clicked (+Move_Button);
         Check_Editor_Log ("Move Clip");
         Clicked (+Place_Button);
         Check_Editor_Log ("Add Selected Media to Track");
         Import_Selected (Files (Test_Dir & "/bad path.mp4"));
         Check_Editor_Log ("Import Files");
         Open_Selected (Files (Test_Dir & "/bad path.fw"));
         Check_Editor_Log ("Open Project");
         Save_Selected (Files (Test_Dir & "/bad path.fw"));
         Check_Editor_Log ("Save Project");
         Export_Selected (Files (Test_Dir & "/bad path.mp4"));
         Check_Editor_Log ("Export Video");
         Check (History = Initial_History and then not Dirty and then
           not Dialogs.Is_Shown (Form) and then not Dialogs.Is_Shown (Console_Dialog),
           "Validation logging must not run commands or open dialogs");
         Check (Ada.Strings.Fixed.Count (Adi.Widget.Text_Editor.Get_Text (Console_Output),
           Ada.Characters.Latin_1.LF & "err ") = 7, "Every validation entry has an error response");
         declare
            Before : constant String := Adi.Widget.Text_Editor.Get_Text (Console_Output);
         begin
            Import_Selected (Adi.OS.Empty_Strings);
            Open_Selected (Adi.OS.Empty_Strings);
            Save_Selected (Adi.OS.Empty_Strings);
            Export_Selected (Adi.OS.Empty_Strings);
            Check (Adi.Widget.Text_Editor.Get_Text (Console_Output) = Before,
                   "Canceled file pickers do not create phantom command entries");
         end;

         Stage ("import callback, filters and canceled import");
         Import_Selected (Files (Test_Dir & "/video.mp4"));
         Check (Dialogs.Is_Shown (Form), "Import should request duration");
         Inputs.Set_Text (Values (2), "3");
         Apply;
         Check (Reply.Ok, "Video import should succeed");
         Check_Editor_Log ("import " & US.To_String (Form_Target) & " " & Test_Dir & "/video.mp4 3 video");
         Execute_Line ("import music " & Test_Dir & "/audio.wav 3 audio");
         Check (Reply.Ok, "Audio registration");
         Execute_Line ("import combined " & Test_Dir & "/both.mp4 3 both");
         Check (Reply.Ok, "Combined media registration");
         Initial_History := History;
         Check (Combos.Option_Count (Source_Choice) = 3, "All filter source count");
         Clicked (+Filter_Buttons (Video_Media));
         Check (Combos.Option_Count (Source_Choice) = 2, "Video includes combined media");
         Check (Ada.Strings.Fixed.Index (Adi.Widget.Text_Editor.Get_Text (Sources), "music") = 0,
                "Audio-only sources hidden by Video");
         Clicked (+Filter_Buttons (Audio_Media));
         Check (Combos.Option_Count (Source_Choice) = 2, "Audio includes combined media");
         Check (Has_State (+Filter_Buttons (Audio_Media), State_Selected), "Active filter highlight");
         Clicked (+Filter_Buttons (All_Media));
         Import_Selected (Adi.OS.Empty_Strings);
         Check (History = Initial_History, "Filtering/canceling import must not edit the document");

         Stage ("named tracks, dialog width, caret and invalid names");
         Clicked (+Add_Track_Button);
         Render (W);
         Check (Field (1)'Length > 0, "Generated track name default");
         Check (Get_Focus_Handle (W) = Widget_Handle'(+Values (1)), "Track name initial focus");
         Check (Get_Geometry (+Values (1)).Width = Get_Geometry (+Kind_Choice).Width,
                "Track name and media kind must have equal widths");
         declare
            Caret_Visible : Boolean := False;
         begin
            for I in 1 .. Item_Count (+Values (1)) loop
               declare
                  Drawn : constant Item := Get_Item (+Values (1), I);
               begin
                  Caret_Visible := Caret_Visible or else
                    (Drawn.Part = Cursor_Part and then Drawn.Geometry.Width > 0.0
                     and then Drawn.Geometry.Height > 0.0);
               end;
            end loop;
            Check (Caret_Visible, "Focused name field must draw a caret");
         end;
         Inputs.Set_Text (Values (1), "Main_Video");
         Apply;
         Check (Reply.Ok and then not Dialogs.Is_Shown (Form), "Named track creation");
         Check_Editor_Log ("track Main_Video video");
         Check (Framewise.Image (FS.Sequence_Of (Editor).Tracks (1).N) = "Main_Video",
                "Entered track name must reach the model");
         Initial_History := History;
         Clicked (+Add_Track_Button);
         Inputs.Set_Text (Values (1), "Main_Video");
         Apply;
         Check (not Reply.Ok and then Dialogs.Is_Shown (Form), "Duplicate name rejected");
         Inputs.Set_Text (Values (1), "Bad Name");
         Apply;
         Check (History = Initial_History, "Invalid names must not edit the document");
         Inputs.Set_Text (Values (1), "");
         Apply;
         Check (History = Initial_History, "Empty name rejected");
         Inputs.Set_Text (Values (1), "abcdefghijklmnopqrstuvwxyz1234567");
         Apply;
         Check (History = Initial_History, "Overlong name rejected");
         Check_Editor_Log ("Add Track", 3);
         Form_Result (Null_Handle, 2, "Cancel");

         Stage ("clip placement, numeric move, rejected overlap and undo");
         Combos.Set_Selected_Index (Source_Choice, 1);
         Combos.Set_Selected_Index (Track_Choice, 1);
         Clicked (+Place_Button);
         Clip_Name := Form_Target;
         Inputs.Set_Text (Values (1), "0");
         Inputs.Set_Text (Values (2), "2");
         Inputs.Set_Text (Values (3), "0");
         Apply;
         Check (Reply.Ok, "Place selected media");
         Check_Editor_Log ("place " & US.To_String (Clip_Name) & " Main_Video " &
           Combos.Get_Selected_Text (Source_Choice) & " 0 2 0");
         declare
            T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            T.Selected_Clip := Clip_Name;
         end;
         Clicked (+Move_Button);
         Inputs.Set_Text (Values (1), "0.5");
         Apply;
         Check (Reply.Ok, "Numeric move");
         Check_Editor_Log ("move " & US.To_String (Clip_Name) & " 0.5");
         Check (FS.Sequence_Of (Editor).Tracks (1).Clips (1).Start = Framewise.Timebase / 2,
                "Move start applied");
         Clicked (+Undo_Button);
         Check (FS.Sequence_Of (Editor).Tracks (1).Clips (1).Start = 0, "Undo move");
         Check_Editor_Log ("undo");
         Initial_History := History;
         Clicked (+Place_Button);
         Inputs.Set_Text (Values (1), "0");
         Inputs.Set_Text (Values (2), "2");
         Inputs.Set_Text (Values (3), "1");
         Apply;
         Check (not Reply.Ok and then Dialogs.Is_Shown (Form), "Overlap must be rejected");
         Check (History = Initial_History, "Rejected placement must not edit history");
         Form_Result (Null_Handle, 2, "Cancel");

         Stage ("Razor selected state and transport navigation");
         Clicked (+Razor_Button);
         Check (Has_State (+Razor_Button, State_Selected), "Razor active highlight");
         Clicked (+Razor_Button);
         Check (not Has_State (+Razor_Button, State_Selected), "Razor inactive highlight");
         Check (not Is_Visible (+Tool_Status) and then Labels.Get_Text (Tool_Status) = "",
                "Leaving Razor mode does not restore the removed Select instruction");
         Clicked (+End_Button);
         declare
            T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Check (T.Playhead = 2 * Framewise.Timebase, "Go to project end");
         end;
         Clicked (+Start_Button);
         declare
            T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Check (T.Playhead = 0, "Go to beginning");
         end;
         Check (History = Initial_History, "Tool and transport controls must not edit history");

         Stage ("settings and real export callback");
         Menu_Selected (File_Menu, 6, "Project Settings");
         Inputs.Set_Text (Values (1), "320");
         Inputs.Set_Text (Values (2), "180");
         Inputs.Set_Text (Values (3), "24");
         Apply;
         Check (Reply.Ok and then FS.Settings_Of (Editor).Width = 320, "Settings dialog");
         Check_Editor_Log ("settings 320 180 24");
         Export_Selected (Files (Test_Dir & "/export.mp4"));
         Check (Reply.Ok and then Ada.Directories.Exists (Test_Dir & "/export.mp4"), "Real GUI export");
         Check_Editor_Log ("export " & Test_Dir & "/export.mp4");
         Initial_History := History;
         Export_Selected (Files (Test_Dir & "/missing/export.mp4"));
         Check (not Reply.Ok, "Failed export must report failure");
         Check_Editor_Log ("export " & Test_Dir & "/missing/export.mp4");
         Export_Selected (Adi.OS.Empty_Strings);
         Check (History = Initial_History, "Export/failure/cancel must not edit project");

         Stage ("save, save-as, cancel, dirty state and reopen");
         Save_Selected (Files (Test_Dir & "/first"));
         Check (US.To_String (Project_Path) = Test_Dir & "/first.fw", "First save adds extension");
         Check_Editor_Log ("save " & Test_Dir & "/first.fw");
         Check (not Dirty, "Successful save clears dirty state");
         Save_Selected (Adi.OS.Empty_Strings);
         Check (US.To_String (Project_Path) = Test_Dir & "/first.fw", "Canceled save keeps path");
         Execute_Line ("track Extra audio");
         Check (Dirty, "Editing marks project dirty");
         Request_Action (New_Project);
         Check (Dialogs.Is_Shown (Confirm), "New must protect unsaved edits");
         Confirm_Result (Null_Handle, 2, "Cancel");
         Dialogs.Hide (Confirm);
         Check (Dirty and then FS.Sequence_Of (Editor).Tracks (2).Used, "Cancel retains project");
         Request_Action (Open_Project);
         Check (Dialogs.Is_Shown (Confirm), "Open must protect unsaved edits");
         Confirm_Result (Null_Handle, 2, "Cancel");
         Dialogs.Hide (Confirm);
         Check (Dirty, "Cancel open keeps unsaved edits");
         declare
            Allowed : Boolean := True;
         begin
            Close_Requested (W, Allowed);
            Check (not Allowed and then Dialogs.Is_Shown (Confirm), "Close protects unsaved project");
            Confirm_Result (Null_Handle, 2, "Cancel");
            Dialogs.Hide (Confirm);
         end;
         Save_Project;
         Check (not Dirty, "Save writes to current path");
         Check_Editor_Log ("save " & Test_Dir & "/first.fw", 2);
         Save_Selected (Files (Test_Dir & "/gui.fw"));
         Check (US.To_String (Project_Path) = Test_Dir & "/gui.fw", "Save As changes active path");
         Check_Editor_Log ("save " & Test_Dir & "/gui.fw");
         Check (Interfaces.C.Strings.Value (Native_Title (Get_SDL_Window (W))) = "Framewise gui",
                "Save As updates native window title");
         Execute_Line ("track Temporary audio");
         Clicked (+Undo_Button);
         Check (not Dirty, "Undo to saved state clears dirty flag");
         Execute_Line ("track Gui_Only audio");
         Save_Project;
         Check (not Dirty, "Save after Save As uses new current document");
         Request_Action (New_Project);
         Check (FS.History_Length (Editor) = 0 and then US.Length (Project_Path) = 0, "New clears project");
         Check_Editor_Log ("New Project");
         Open_Selected (Files (Test_Dir & "/first.fw"));
         Check (Reply.Ok and then FS.Sequence_Of (Editor).Tracks (2).Used, "Save persisted later edit");
         Check (not FS.Sequence_Of (Editor).Tracks (3).Used, "Save As must preserve original document");
         Check (Interfaces.C.Strings.Value (Native_Title (Get_SDL_Window (W))) = "Framewise first",
                "Open updates native window title");
         Open_Selected (Files (Test_Dir & "/gui.fw"));
         Check (Reply.Ok and then not Dirty, "Reopen saved project");
         Check (Framewise.Image (FS.Sequence_Of (Editor).Tracks (3).N) = "Gui_Only",
                "Save after Save As persisted only in the new file");
         Initial_History := History;
         Open_Selected (Adi.OS.Empty_Strings);
         Check (History = Initial_History, "Cancel open retains project");

         Stage ("resizing dividers through window event routing");
         Render (W);
         declare
            G : constant Rectangle := Get_Geometry (+Workspace);
            Before : constant Pixel_Type := G.Height;
         begin
            Adi.Window.On_Mouse_Down (W, G.X + 20.0, G.Y + G.Height + 4.0, Left_Button);
            Adi.Window.On_Mouse_Move (W, G.X + 20.0, G.Y + G.Height - 60.0);
            Adi.Window.On_Mouse_Up (W, G.X + 20.0, G.Y + G.Height - 60.0, Left_Button);
            Render (W);
            Check (Get_Geometry (+Workspace).Height < Before, "Horizontal divider must drag");
         end;
         declare
            G : constant Rectangle := Get_Geometry (+Bin);
         begin
            Adi.Window.On_Mouse_Down (W, G.X + G.Width + 4.0, G.Y + 20.0, Left_Button);
            Adi.Window.On_Mouse_Move (W, G.X + G.Width + 50.0, G.Y + 20.0);
            Adi.Window.On_Mouse_Up (W, G.X + G.Width + 50.0, G.Y + 20.0, Left_Button);
            Render (W);
            Check (Get_Geometry (+Bin).Width > G.Width, "Vertical divider must drag");
         end;
         Assert_Centered;
         Check (History = Initial_History, "Resizing must not edit document");

         Stage ("scrollbar routed drag and track click must not edit clips");
         Open_Selected (Files ("examples/cut.fw"));
         Check (Reply.Ok, "Open bundled example");
         for I in 1 .. 6 loop
            Execute_Line ("track overflow" & Ada.Strings.Fixed.Trim (I'Image, Ada.Strings.Both));
            Check (Reply.Ok, "Create overflowing tracks");
         end loop;
         Render (W);
         Initial_History := History;
         declare
            G : constant Rectangle := Get_Geometry (+Track_Scroll);
         begin
            Check (Get_Scroll_Max_Offset_Y (+Track_Scroll) > 0.0, "Tracks must overflow");
            Adi.Window.On_Mouse_Down (W, G.X + G.Width - 7.0, G.Y + 10.0, Left_Button);
            Adi.Window.On_Mouse_Move (W, G.X + G.Width - 7.0, G.Y + G.Height);
            Adi.Window.On_Mouse_Up (W, G.X + G.Width - 7.0, G.Y + G.Height, Left_Button);
            Check (Get_Scroll_Offset_Y (+Track_Scroll) > 0.0, "Scrollbar thumb must drag through window routing");
            Set_Scroll_Offset_Y (+Track_Scroll, 0.0);
            Render (W);
            Adi.Window.On_Mouse_Down (W, G.X + G.Width - 7.0, G.Y + G.Height - 10.0, Left_Button);
            Adi.Window.On_Mouse_Up (W, G.X + G.Width - 7.0, G.Y + G.Height - 10.0, Left_Button);
            Check (Get_Scroll_Offset_Y (+Track_Scroll) > 0.0, "Clicking scrollbar track must page");
            Check (History = Initial_History, "Scrollbar must not edit history");
            declare
               T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
            begin
               Check (not T.Drag_Active and then not T.Scrubbing, "Scrollbar must not start a clip gesture");
            end;
         end;
         Request_Action (New_Project);
         Check (Dialogs.Is_Shown (Confirm), "Dirty overflow project discard prompt");
         Confirm_Result (Null_Handle, 1, "Discard");
         Dialogs.Hide (Confirm);
         Render (W);
         Check (Get_Scroll_Max_Offset_Y (+Track_Scroll) = 0.0, "Empty timeline hides scrollbar");
         Check (Get_Scroll_Offset_Y (+Track_Scroll) = 0.0, "Old scroll offset cleared");
         Check (Current_Filter = All_Media, "New resets filter");
         Stage ("console opening, caret, routed typing and command execution");
         declare
            procedure Press_Enter is
            begin
               Adi.Window.On_Key_Down
                 (W, Adi.SDL.Events.SDL_SCANCODE_RETURN, 0, 0, False);
            end Press_Enter;

            procedure Click_Control (H : Widget_Handle) is
               G : constant Rectangle := Get_Geometry (H);
            begin
               Adi.Window.On_Mouse_Down (W, G.X + G.Width / 2.0, G.Y + G.Height / 2.0, Left_Button);
               Adi.Window.On_Mouse_Up (W, G.X + G.Width / 2.0, G.Y + G.Height / 2.0, Left_Button);
            end Click_Control;

            procedure Command (Line : String) is
            begin
               Adi.Window.On_Text_Input (W, Line);
               Press_Enter;
               Check (Inputs.Get_Text (Console_Input) = "", "Submitted input clears");
               Check (Get_Focus_Handle (W) = Widget_Handle'(+Console_Input), "Input retains focus");
            end Command;

            Caret_Visible : Boolean := False;
            Before : US.Unbounded_String;
         begin
            Check (Get_Geometry (+Console_Button).X > Get_Geometry (+File_Button).X + 500.0,
                   "Console button belongs at far right of top bar");
            Click_Control (+Console_Button);
            Render (W);
            Check (Dialogs.Is_Shown (Console_Dialog), "Console button opens centered dialog");
            Check (Overlay_Count (W) = 1, "Console must block editor interaction");
            Check (Ada.Strings.Fixed.Index
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "[Editor] load examples/cut.fw") > 0,
              "Project opens before first console use must be recorded");
            Check (Get_Focus_Handle (W) = Widget_Handle'(+Console_Input), "Console opens ready to type");
            for I in 1 .. Item_Count (+Console_Input) loop
               declare
                  Drawn : constant Item := Get_Item (+Console_Input, I);
               begin
                  Caret_Visible := Caret_Visible or else
                    (Drawn.Part = Cursor_Part and then Drawn.Geometry.Width > 0.0
                     and then Drawn.Geometry.Height > 0.0);
               end;
            end loop;
            Check (Caret_Visible, "Empty console input must draw a visible caret");
            Stage ("console scrollbar mouse drag and track paging");
            declare
               G : constant Rectangle := Geometry_In_Window (+Console_Output);
               Initial_History : constant US.Unbounded_String := History;
               Transcript : constant String := Adi.Widget.Text_Editor.Get_Text (Console_Output);
            begin
               Check (Get_Scroll_Max_Offset_Y (+Console_Output) > 0.0,
                      "Console transcript overflows its viewport");
               Check (Get_Resolved_Part_Style (+Console_Output, Scroll_Part).Background_Color = RGB (22, 29, 40)
                 and then Get_Resolved_Part_Style (+Console_Output, Knob_Part).Background_Color = RGB (115, 135, 160),
                 "Console scrollbar has a contrasting track and thumb");
               Set_Scroll_Offset_Y (+Console_Output, 0.0);
               Render (W);
               --  Route through the modal window rather than calling the text
               --  widget directly: this catches hit-testing and capture bugs.
               Adi.Window.On_Mouse_Down (W, G.X + G.Width - 7.0, G.Y + 10.0, Left_Button);
               Adi.Window.On_Mouse_Move (W, G.X + G.Width - 7.0, G.Y + G.Height);
               Adi.Window.On_Mouse_Up (W, G.X + G.Width - 7.0, G.Y + G.Height, Left_Button);
               Check (Get_Scroll_Offset_Y (+Console_Output) > 0.0,
                      "Console scrollbar thumb drags through modal event routing");
               Set_Scroll_Offset_Y (+Console_Output, 0.0);
               Render (W);
               Adi.Window.On_Mouse_Down (W, G.X + G.Width - 7.0, G.Y + G.Height - 10.0, Left_Button);
               Adi.Window.On_Mouse_Up (W, G.X + G.Width - 7.0, G.Y + G.Height - 10.0, Left_Button);
               Check (Get_Scroll_Offset_Y (+Console_Output) > 0.0,
                      "Console scrollbar track click pages the transcript");
               Check (Adi.Widget.Text_Editor.Get_Text (Console_Output) = Transcript,
                      "Scrollbar interaction does not change the transcript");
               Check (History = Initial_History, "Console scrolling does not edit the project");
               Click_Control (+Console_Input);
            end;
            Before := History;
            Command ("   ");
            Check (History = Before, "Blank console command must not change project");
            Inputs.Set_Text (Console_Input, "");
            Adi.Window.On_Text_Input (W, "track consoleTrack video");
            Adi.Window.On_Key_Down (W, Adi.SDL.Events.SDL_SCANCODE_RETURN, 0, 0, True);
            Check (History = Before, "Repeated Enter must not execute a command");
            Press_Enter;
            Check (Reply.Ok and then Dirty, "Console edits the shared project");
            Check (Combos.Get_Selected_Text (Track_Choice) = "consoleTrack", "Console refreshes track dropdown");
            Check (Ada.Strings.Fixed.Index
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "[Console] track consoleTrack video") > 0,
              "Transcript includes entered command");
            Before := History;
            Command ("list");
            Check (Reply.Ok and then History = Before, "Read-only commands retain project history");
            Command ("not_a_command");
            Check (not Reply.Ok and then History = Before, "Console reports rejected commands safely");
            Check (Ada.Strings.Fixed.Index
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "err ") > 0, "Transcript includes errors");
            Adi.Window.On_Key_Down
              (W, Adi.SDL.Events.SDL_SCANCODE_Z, 0, Adi.SDL.Events.SDL_KMOD_CTRL, False);
            Check (History = Before, "Console text shortcuts must not undo project edits");

            Inputs.Set_Text (Console_Input, "");
            Command ("save " & Test_Dir & "/console.fw");
            Check (Reply.Ok and then not Dirty, "Console save clears dirty state");
            Check (US.To_String (Project_Path) = Test_Dir & "/console.fw", "Console save updates project path");
            Command ("save " & Test_Dir & "/missing/console.fw");
            Check (not Reply.Ok and then not Dirty and then
              US.To_String (Project_Path) = Test_Dir & "/console.fw",
              "Failed console save must preserve current document bookkeeping");
            Command ("load " & Test_Dir & "/missing.fw");
            Check (not Reply.Ok and then not Dirty and then History = Before,
                   "Missing console load preserves project and saved state");
            Command ("track extra audio");
            Check (Reply.Ok and then Dirty, "Edit after save marks project dirty");
            Command ("load " & Test_Dir & "/console.fw");
            Check (Reply.Ok and then not Dirty and then History = Before, "Console load restores saved document");
            Check (Interfaces.C.Strings.Value (Native_Title (Get_SDL_Window (W))) = "Framewise console",
                   "Console load updates native title");
            Command ("undo");
            Check (Reply.Ok and then Dirty, "Console undo refreshes dirty state");
            Render (W);
            Before := US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output));
            Click_Control (+Console_Close_Button);
            Check (not Dialogs.Is_Shown (Console_Dialog), "Close dismisses console");
            Check (Get_Focus_Handle (W) = Widget_Handle'(+Tracks), "Close returns focus to editor");
            Render (W);
            Click_Control (+Console_Button);
            Render (W);
            Check (US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output)) = Before,
                   "Console transcript persists when reopened");
            Adi.Window.On_Text_Input (W, "list");
            Click_Control (+Console_Run_Button);
            Check (Reply.Ok and then Inputs.Get_Text (Console_Input) = "", "Run button submits input");
            Stage ("incomplete plan after opening cut.fw must not crash the console");
            Click_Control (+Console_Close_Button);
            Open_Selected (Files ("examples/cut.fw"));
            Check (Reply.Ok, "Open cut.fw through the project picker callback");
            Before := History;
            Render (W);
            Click_Control (+Console_Button);
            Render (W);
            Command ("plan");
            Check (not Reply.Ok and then History = Before and then not Dirty,
                   "Incomplete plan returns an error without changing the loaded project");
            Check (Ada.Strings.Fixed.Index
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "err bad arguments for plan") > 0,
              "Console transcript explains rejected plan");
            Command ("plan " & Test_Dir & "/planned.mp4");
            Check (Reply.Ok and then History = Before and then not Dirty,
                   "Console accepts a valid plan immediately after an incomplete command");
            Stage ("editor command logging without interrupting console typing");
            Inputs.Set_Text (Console_Input, "info c");
            Set_Focus (W, +Console_Input);
            Adi.Window.On_Key_Down (W, Adi.SDL.Events.SDL_SCANCODE_LEFT, 0, 0, False);
            Execute_Line ("track Background video");
            Check (Reply.Ok and then Inputs.Get_Text (Console_Input) = "info c",
                   "Incoming editor output preserves unfinished input");
            Check (Get_Focus_Handle (W) = Widget_Handle'(+Console_Input), "Logging must not change focus");
            Adi.Window.On_Text_Input (W, "1");
            Check (Inputs.Get_Text (Console_Input) = "info 1c", "Logging preserves caret insertion position");
            Check (Ada.Strings.Fixed.Count
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "[Editor] track Background video") = 1,
              "Editor command logged once under editor origin");
            Inputs.Set_Text (Console_Input, "");

            Stage ("centered modal console blocks background interaction");
            Render (W);
            declare
               G : constant Rectangle := Get_Geometry (+Console_Panel);
               Size : constant Size_2D := Get_Size (W);
               V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
               Old_Zoom : constant Long_Float := V.Zoom;
               Saved : constant US.Unbounded_String := History;
               Track_G : constant Rectangle := Geometry_In_Window (+Tracks);
            begin
               Check (abs (G.X + G.Width / 2.0 - Size.Width / 2.0) < 1.0 and then
                 abs (G.Y + G.Height / 2.0 - Size.Height / 2.0) < 1.0,
                 "Console is centered on the editor window");
               Click_Control (+Add_Track_Button);
               Check (not Dialogs.Is_Shown (Form), "Modal console blocks Add Track button");
               Click_Control (+Undo_Button);
               Click_Control (+Zoom_In);
               Click_Control (+File_Button);
               Adi.Window.On_Mouse_Down (W, Track_G.X + 160.0, Track_G.Y + 50.0, Left_Button);
               Adi.Window.On_Mouse_Move (W, Track_G.X + 190.0, Track_G.Y + 50.0);
               Adi.Window.On_Mouse_Up (W, Track_G.X + 190.0, Track_G.Y + 50.0, Left_Button);
               Check (History = Saved and then V.Zoom = Old_Zoom,
                      "Backdrop blocks editor edits and navigation");
               Check (not V.Drag_Active and then not V.Scrubbing,
                      "Backdrop blocks timeline gestures");
               Check (Dialogs.Is_Shown (Console_Dialog) and then Overlay_Count (W) = 1,
                      "Background clicks neither dismiss console nor open File menu");
            end;
            Set_Focus (W, +Console_Input);
            Execute_Line ("move c1 5");
            Check (not Reply.Ok and then Ada.Strings.Fixed.Index
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "[Editor] move c1 5" &
               Ada.Characters.Latin_1.LF & FS.Image (Reply)) > 0,
              "Rejected editor edits include their error response");
            Save_Selected (Files (Test_Dir & "/observed.fw"));
            Check (Reply.Ok and then Ada.Strings.Fixed.Count
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "[Editor] save " & Test_Dir & "/observed.fw") = 1,
              "Editor saves are logged once");
            Inputs.Set_Text (Console_Input, "draft");
            Before := US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output));
            Render (W);
            Click_Control (+Console_Close_Button);
            Stage ("project opens and clip deletion remain logged with console closed");
            Open_Selected (Files ("examples/cut.fw"));
            Check (Reply.Ok and then not Dialogs.Is_Shown (Console_Dialog),
                   "Open Project callback works while console stays closed");
            Render (W);
            declare
               G : constant Rectangle := Geometry_In_Window (+Tracks);
               V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
               Step : constant Pixel_Type := Pixel_Type (V.Zoom);
            begin
               Adi.Window.On_Mouse_Down (W, G.X + 110.0 + 2.0 * Step, G.Y + 50.0, Left_Button);
               Adi.Window.On_Mouse_Up (W, G.X + 110.0 + 2.0 * Step, G.Y + 50.0, Left_Button);
               Check (US.To_String (V.Selected_Clip) = "c1", "Select first clip through editor");
               Click_Control (+Delete_Button);
               Check (Reply.Ok and then Natural (FS.Sequence_Of (Editor).Tracks (1).Count) = 2,
                      "Delete Clip button removes the selected clip");
               Check (Ada.Strings.Fixed.Index
                 (Adi.Widget.Text_Editor.Get_Text (Console_Output), "[Editor] delete c1" &
                  Ada.Characters.Latin_1.LF & FS.Image (Reply)) > 0,
                 "Closed-console log includes deletion and result");
               Render (W);
               Adi.Window.On_Mouse_Down (W, G.X + 110.0 + 10.0 * Step, G.Y + 50.0, Left_Button);
               Adi.Window.On_Mouse_Up (W, G.X + 110.0 + 10.0 * Step, G.Y + 50.0, Left_Button);
               Check (US.To_String (V.Selected_Clip) = "c2", "Select second clip through editor");
               Adi.Window.On_Key_Down (W, Adi.SDL.Events.SDL_SCANCODE_DELETE, 0, 0, False);
               Check (Reply.Ok and then Natural (FS.Sequence_Of (Editor).Tracks (1).Count) = 1,
                      "Delete key removes the selected clip");
            end;
            Check (not Dialogs.Is_Shown (Console_Dialog) and then
              Get_Focus_Handle (W) = Widget_Handle'(+Tracks),
              "Background recording must not open console or steal editor focus");
            declare
               Recorded : constant String := Adi.Widget.Text_Editor.Get_Text (Console_Output);
            begin
               Check (Ada.Strings.Fixed.Count (Recorded, "[Editor] load examples/cut.fw") =
                 Ada.Strings.Fixed.Count (US.To_String (Before), "[Editor] load examples/cut.fw") + 1,
                 "Open Project recorded exactly once");
               Check (Ada.Strings.Fixed.Count (Recorded, "[Editor] delete c1") =
                 Ada.Strings.Fixed.Count (US.To_String (Before), "[Editor] delete c1") + 1,
                 "Button deletion recorded exactly once");
               Check (Ada.Strings.Fixed.Count (Recorded, "[Editor] delete c2") =
                 Ada.Strings.Fixed.Count (US.To_String (Before), "[Editor] delete c2") + 1,
                 "Keyboard deletion recorded exactly once");
               Before := US.To_Unbounded_String (Recorded);
            end;
            Render (W);
            Click_Control (+Zoom_In);
            Click_Control (+Filter_Buttons (Video_Media));
            Check (US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output)) = Before,
                   "Navigation and filters remain excluded while console is closed");
            Click_Control (+Console_Button);
            Render (W);
            Check (US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output)) = Before,
                   "Reopening console displays recorded actions without duplication");
            Check (Inputs.Get_Text (Console_Input) = "draft", "Reopening preserves draft input");
            Inputs.Set_Text (Console_Input, "");
            Before := US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output));
            Command ("list");
            Check (Ada.Strings.Fixed.Count
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "[Console] list") =
              Ada.Strings.Fixed.Count (US.To_String (Before), "[Console] list") + 1,
              "Console command logged once under console origin");
            Check (Ada.Strings.Fixed.Index
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "[Editor] list") = 0,
              "Console commands must not be duplicated as editor actions");
            Adi.Window.Handle_Resize (W, (960.0, 650.0));
            Render (W);
            declare
               G : constant Rectangle := Get_Geometry (+Console_Input);
            begin
               Check (G.Width > 0.0 and then G.Height > 0.0 and then
                 G.X >= 0.0 and then G.X + G.Width <= 960.0 and then
                 G.Y >= 0.0 and then G.Y + G.Height <= 650.0,
                 "Console input remains accessible in a smaller window");
               declare
                  Panel : constant Rectangle := Get_Geometry (+Console_Panel);
               begin
                  Check (abs (Panel.X + Panel.Width / 2.0 - 480.0) < 1.0 and then
                    abs (Panel.Y + Panel.Height / 2.0 - 325.0) < 1.0,
                    "Modal console stays centered after window resize");
               end;
            end;
            Adi.Window.On_Key_Down (W, Adi.SDL.Events.SDL_SCANCODE_ESCAPE, 0, 0, False);
            Check (not Dialogs.Is_Shown (Console_Dialog), "Escape dismisses console");

            Stage ("released timeline gestures use the same editor log");
            Open_Selected (Files ("examples/cut.fw"));
            Render (W);
            declare
               G : constant Rectangle := Geometry_In_Window (+Tracks);
               V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
               Step : constant Pixel_Type := Pixel_Type (V.Zoom);
               X : constant Pixel_Type := G.X + 110.0 + 2.0 * Step;
               Y : constant Pixel_Type := G.Y + 50.0;
               Edge : constant Pixel_Type := G.X + 110.0 + 7.5 * Step - 1.0;
            begin
               Before := US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output));
               Adi.Window.On_Mouse_Down (W, X, Y, Left_Button);
               Adi.Window.On_Mouse_Move (W, X + Step / 2.0, Y);
               Adi.Window.On_Mouse_Move (W, X + Step, Y);
               Check (US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output)) = Before,
                      "Drag motion is not logged until release");
               Adi.Window.On_Mouse_Up (W, X + Step, Y, Left_Button);
               Check (Reply.Ok, "Move gesture succeeds");
               Check_Editor_Log ("move c1 1");
               Render (W);
               Adi.Window.On_Mouse_Down (W, Edge, Y, Left_Button);
               Adi.Window.On_Mouse_Move (W, Edge - Step / 2.0, Y);
               Adi.Window.On_Mouse_Up (W, Edge - Step / 2.0, Y, Left_Button);
               Check (Reply.Ok, "Trim gesture succeeds");
               Check_Editor_Log ("trim c1 2 8");
               Render (W);
               Clicked (+Razor_Button);
               Adi.Window.On_Mouse_Down (W, G.X + 110.0 + 3.0 * Step, Y, Left_Button);
               Adi.Window.On_Mouse_Up (W, G.X + 110.0 + 3.0 * Step, Y, Left_Button);
               Check (Reply.Ok, "Razor split succeeds");
               Check_Editor_Log ("split c1 3 r1");
               Clicked (+Razor_Button);
            end;
         end;
         Ada.Text_IO.Put_Line ("PASS: editor workflow regression scenarios");
      end;
