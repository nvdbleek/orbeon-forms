/**
 * Copyright (C) 2011 Orbeon, Inc.
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

package org.orbeon.oxf.xforms.processor

import org.orbeon.oxf.pipeline.api.{XMLReceiver, PipelineContext}
import org.orbeon.oxf.xml._
import java.lang.String
import org.xml.sax.Attributes
import net.sf.ehcache.{Element => EhElement }
import org.orbeon.oxf.common.Version
import org.xml.sax.helpers.AttributesImpl
import org.orbeon.oxf.util._
import scala.collection.JavaConversions._
import org.orbeon.oxf.processor._
import collection.mutable.{Buffer, LinkedHashSet}
import org.orbeon.oxf.xforms.{XFormsProperties, Caches}

/**
 * Aggregate CSS and JS resources under <head>.
 */
class ResourcesAggregator extends ProcessorImpl {

    addInputInfo(new ProcessorInputOutputInfo(ProcessorImpl.INPUT_DATA))
    addOutputInfo(new ProcessorInputOutputInfo(ProcessorImpl.OUTPUT_DATA))

    override def createOutput(name: String) = {
        val output = new ProcessorOutputImpl(ResourcesAggregator.this, name) {
            override def readImpl(pipelineContext: PipelineContext, xmlReceiver: XMLReceiver) =
                readInputAsSAX(pipelineContext, ProcessorImpl.INPUT_DATA,
                    if (!XFormsProperties.isCombinedResources) xmlReceiver else new SimpleForwardingXMLReceiver(xmlReceiver) {

                    case class InlineElement(attributes: Attributes) {
                        var content = new StringBuilder
                    }

                    val attributesImpl = new AttributesImpl

                    // State
                    var level = 0
                    var inHead = false
                    var filter = false

                    var currentInlineElement: InlineElement = _

                    // Resources gathered
                    var baselineCSS = LinkedHashSet[String]()
                    var baselineJS = LinkedHashSet[String]()
                    var css = LinkedHashSet[String]()
                    var js = LinkedHashSet[String]()

                    var inlineCSS = Buffer[InlineElement]()
                    var inlineJS = Buffer[InlineElement]()

                    override def startElement(uri: String, localname: String, qName: String, attributes: Attributes) = {
                        level += 1

                        if (level == 2 && localname == "head") {
                            inHead = true
                        } else if (level == 3 && inHead) {

                            lazy val href = attributes.getValue("href")
                            lazy val src = attributes.getValue("src")
                            lazy val resType = attributes.getValue("type")
                            lazy val cssClasses = attributes.getValue("class")

                            // Gather resources that match
                            localname match {
                                case "link" if (href ne null) && ((resType eq null) || resType == "text/css") =>
                                    (if (cssClasses == "xforms-baseline") baselineCSS else css) += href
                                    filter = true
                                case "script" if (src ne null) && ((resType eq null) || resType == "text/javascript")  =>
                                    (if (cssClasses == "xforms-baseline") baselineJS else js) += src
                                    filter = true
                                case "style" if (resType eq null) =>
                                    currentInlineElement = InlineElement(new AttributesImpl(attributes))
                                    inlineCSS += currentInlineElement
                                    filter = true
                                case "script" if (src eq null) =>
                                    currentInlineElement = InlineElement(new AttributesImpl(attributes))
                                    inlineJS += currentInlineElement
                                    filter = true
                                case _ =>
                            }
                        }

                        if (!filter)
                            super.startElement(uri, localname, qName, attributes)
                    }

                    override def endElement(uri: String, localname: String, qName: String) = {

                        lazy val xhtmlPrefix = XMLUtils.prefixFromQName(qName)
                        lazy val helper = new ContentHandlerHelper(xmlReceiver)

                        // Configurable function to output an element
                        def outputElement(getAttributes: String => Array[String], elementName: String)(resource: String) = {
                            attributesImpl.clear()
                            ContentHandlerHelper.populateAttributes(attributesImpl, getAttributes(resource))
                            helper.element(xhtmlPrefix, XMLConstants.XHTML_NAMESPACE_URI, elementName, attributesImpl)
                        }

                        // Output an inline element
                        def outputInlineElement(elementName: String, element: InlineElement) = {
                            helper.startElement(xhtmlPrefix, XMLConstants.XHTML_NAMESPACE_URI, elementName, element.attributes)
                            helper.text(element.content.toString)
                            helper.endElement()
                        }

                        // Output combined resources
                        def outputCombined(resources: scala.collection.Set[String], isCSS: Boolean, outputElement: String => Unit) {
                            if (resources.nonEmpty) {
                                // If there is at least one non-platform path, we also hash the app version number
                                val hasAppResource = resources exists (!URLRewriterUtils.isPlatformPath(_))

                                // All resource paths are hashed
                                val itemsToHash = resources ++ (if (hasAppResource) Set(URLRewriterUtils.getApplicationResourceVersion) else Set())
                                val resourcesHash = ScalaUtils.digest("SHA-1", Seq(itemsToHash mkString "|"))

                                // Cache mapping so that resource can be served by oxf:resource-server
                                Caches.resourcesCache.put(new EhElement(resourcesHash, resources.toArray)) // use Array which is serializable and usable from Java

                                // Output link to resource
                                val path = "" :: "xforms-server" ::
                                    (if (URLRewriterUtils.isResourcesVersioned) List(Version.getVersionNumber) else Nil) :::
                                    "orbeon-" + resourcesHash + (if (isCSS) ".css" else ".js") :: Nil

                                outputElement(path mkString "/")

                                // Store on disk if requested to make the resource available to external software, like Apache
                                if (XFormsProperties.isCacheCombinedResources) {
                                    val resourcesConfig = resources map (r => new XFormsFeatures.ResourceConfig(r, r)) toList
                                    val combinedLastModified = XFormsResourceServer.computeCombinedLastModified(resourcesConfig, false)
                                    XFormsResourceServer.cacheResources(resourcesConfig, pipelineContext, resourcesHash, combinedLastModified, isCSS, false)
                                }
                            }
                        }

                        def outputJS = {
                            val outputJSElement = outputElement(resource => Array("type", "text/javascript", "src", resource), "script") _
                            outputCombined(baselineJS, false, outputJSElement)
                            outputCombined(js -- baselineJS, false, outputJSElement)
                            inlineJS foreach (e => outputInlineElement("script", e))
                        }
                        
                        if (level == 2 && localname == "head") {

                            // 1. Combined and inline CSS
                            val outputCSSElement = outputElement(resource => Array("rel", "stylesheet", "href", resource, "type", "text/css", "media", "all"), "link") _
                            outputCombined(baselineCSS, true, outputCSSElement)
                            outputCombined(css -- baselineCSS, true, outputCSSElement)
                            inlineCSS foreach (e => outputInlineElement("style", e))

                            // 2. Combined and inline JS
                            if (!XFormsProperties.isJavaScriptAtBottom)
                                outputJS

                            // Close head element
                            super.endElement(uri, localname, qName)

                            inHead = false
                        } else if (level == 2 && localname == "body") {
                            // Close body element
                            super.endElement(uri, localname, qName)

                            // Combined and inline JS
                            // Scripts at the bottom of the page. This is not valid HTML, but it is a recommended practice for
                            // performance as of early 2008. See http://developer.yahoo.com/performance/rules.html#js_bottom
                            if (XFormsProperties.isJavaScriptAtBottom)
                                outputJS

                        } else if (filter && level == 3 && inHead) {
                            currentInlineElement = null
                            filter = false
                        } else {
                            super.endElement(uri, localname, qName)
                        }

                        level -= 1
                    }

                    override def characters(chars: Array[Char], start: Int, length: Int) =
                        if (filter && level == 3 && inHead && (currentInlineElement ne null))
                            currentInlineElement.content.appendAll(chars, start, length)
                        else
                            super.characters(chars, start, length)
                })

            override def getKeyImpl(pipelineContext: PipelineContext) =
                ProcessorImpl.getInputKey(pipelineContext, getInputByName(ProcessorImpl.INPUT_DATA))

            override def getValidityImpl(pipelineContext: PipelineContext) =
                ProcessorImpl.getInputValidity(pipelineContext, getInputByName(ProcessorImpl.INPUT_DATA))
        }
        addOutput(name, output)
        output
    }
}