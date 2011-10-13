/**
 * Copyright (C) 2010 Orbeon, Inc.
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of the
 * GNU Lesser General Public License as published by the Free Software Foundation; either version
 * 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU Lesser General Public License for more details.
 *
 * The full text of the license is available at http://www.gnu.org/copyleft/lesser.html
 */
package org.orbeon.oxf.xforms.action.actions;

import org.dom4j.Element;
import org.orbeon.oxf.util.IndentedLogger;
import org.orbeon.oxf.xforms.XFormsContainingDocument;
import org.orbeon.oxf.xforms.action.XFormsAction;
import org.orbeon.oxf.xforms.action.XFormsActionInterpreter;
import org.orbeon.oxf.xforms.control.XFormsControl;
import org.orbeon.oxf.xforms.control.controls.XXFormsDialogControl;
import org.orbeon.oxf.xforms.event.XFormsEvent;
import org.orbeon.oxf.xforms.event.XFormsEventObserver;
import org.orbeon.oxf.xforms.event.events.XFormsFocusEvent;
import org.orbeon.oxf.xforms.event.events.XXFormsDialogOpenEvent;
import org.orbeon.oxf.xforms.xbl.XBLBindingsBase;
import org.orbeon.saxon.om.Item;

/**
 * Extension xxforms:show action.
 */
public class XXFormsShowAction extends XFormsAction {

    public void execute(XFormsActionInterpreter actionInterpreter, XFormsEvent event,
                        XFormsEventObserver eventObserver, Element actionElement,
                        XBLBindingsBase.Scope actionScope, boolean hasOverriddenContext, Item overriddenContext) {

        final XFormsContainingDocument containingDocument = actionInterpreter.getContainingDocument();

        // Resolve all attributes as AVTs
        final String dialogStaticOrEffectiveId = actionInterpreter.resolveAVT(actionElement, "dialog");
        final String neighborEffectiveId;
        {
            final String neighborStaticOrEffectiveId = actionInterpreter.resolveAVT(actionElement, "neighbor");
            final XFormsControl neighbor = (XFormsControl) ((neighborStaticOrEffectiveId != null) ? actionInterpreter.resolveOrFindByEffectiveId(actionElement, neighborStaticOrEffectiveId) : null);
            neighborEffectiveId = (neighbor != null) ? neighbor.getEffectiveId() : null;
        }
        final boolean constrainToViewport;
        {
            final String constrain = actionInterpreter.resolveAVT(actionElement, "constrain");
            constrainToViewport = !"false".equals(constrain);
        }

        if (dialogStaticOrEffectiveId != null) {
            // Dispatch xxforms-dialog-open event to dialog
            final Object controlObject = actionInterpreter.resolveOrFindByEffectiveId(actionElement, dialogStaticOrEffectiveId);
            if (controlObject instanceof XXFormsDialogControl) {
                final XXFormsDialogControl targetDialog = (XXFormsDialogControl) controlObject;

                // Remove focus if any
                containingDocument.setClientFocusEffectiveControlId(null);

                final XFormsEvent newEvent = new XXFormsDialogOpenEvent(containingDocument, targetDialog, neighborEffectiveId, constrainToViewport);
                addContextAttributes(actionInterpreter, actionElement, newEvent);
                targetDialog.getXBLContainer(containingDocument).dispatchEvent(newEvent);

                // Check if form author has set focus while dialog was opening, and if not focus on dialog
                final String currentFocusEffectiveId = containingDocument.getClientFocusControlEffectiveId();
                if (currentFocusEffectiveId == null && targetDialog.isVisible())
                    targetDialog.getXBLContainer().dispatchEvent(new XFormsFocusEvent(containingDocument, targetDialog));

            } else {
                final IndentedLogger indentedLogger = actionInterpreter.getIndentedLogger();
                if (indentedLogger.isDebugEnabled())
                    indentedLogger.logDebug("xxforms:show", "dialog does not refer to an existing xxforms:dialog element, ignoring action",
                            "dialog id", dialogStaticOrEffectiveId);
            }
        }
    }
}
