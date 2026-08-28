# Third-party notices

YamabikoChat original code is licensed under the MIT License. See [LICENSE](LICENSE).

This file lists third-party software that is bundled, restored at build time, or otherwise redistributed with YamabikoChat. Those components remain under their own licenses. Short license texts are reproduced at the end of this file. The Node.js composite license is kept separately in [third_party/nodejs-mobile/LICENSE](third_party/nodejs-mobile/LICENSE).

Production npm packages pulled in by the Pi Agent runtime are listed in [third_party/npm-licenses.md](third_party/npm-licenses.md).

## Shared / vendored

| Component | Version / pin | SPDX | Use | Source |
| --- | --- | --- | --- | --- |
| MathJax (`tex-svg.js`) | vendored component build | Apache-2.0 | Chat math rendering | https://github.com/mathjax/MathJax |
| Mermaid (`mermaid.min.js`) | 11.17.2 (`sha256:581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8`) | MIT | Chat diagram rendering | https://github.com/mermaid-js/mermaid |
| `@earendil-works/pi-agent-core` | 0.84.2 | MIT | Pi Agent runtime | https://www.npmjs.com/package/@earendil-works/pi-agent-core |
| `@earendil-works/pi-ai` | 0.84.2 | MIT | Pi Agent runtime | https://www.npmjs.com/package/@earendil-works/pi-ai |
| `pi-grok` | 0.10.1 (`8b304e65c088f84ccb932959d97739245fe47d97`) | MIT | SuperGrok / xAI helper | https://github.com/stnly/pi-grok |
| `typebox` | 1.3.7 | MIT | Pi runtime schemas | https://www.npmjs.com/package/typebox |
| NodeMobile / nodejs-mobile | 24.18.0-0 | Node.js composite (see file) | Embedded Node.js (`libnode.so` / XCFramework) | https://github.com/gmaclennan/nodejs-mobile (Node.js terms: https://github.com/JaneaSystems/nodejs-mobile) |

`markdown-renderer.js` in the MathJax resource folders is original YamabikoChat code (MIT).

MathJax 3 does not ship a `NOTICE` file. Its Apache-2.0 license text is also bundled next to the MathJax assets.

Mermaid's MIT license text is bundled next to the Mermaid browser asset.

## Android libraries

AndroidX, Jetpack Compose, Material, Kotlin, kotlinx libraries, and Google desugar libraries used by this app are licensed under Apache-2.0.

Named non-AndroidX dependencies:

| Component | Version | SPDX | Source |
| --- | --- | --- | --- |
| Markwon (`io.noties.markwon:*`) | 4.6.2 | Apache-2.0 | https://github.com/noties/Markwon |
| AndroidSVG | 1.4 | Apache-2.0 | https://github.com/BigBadaboom/androidsvg |
| SnakeYAML Engine | 3.0.1 | Apache-2.0 | https://bitbucket.org/snakeyaml/snakeyaml-engine |
| Retrofit | 2.9.0 | Apache-2.0 | https://github.com/square/retrofit |
| OkHttp | 4.12.0 | Apache-2.0 | https://github.com/square/okhttp |
| Gson (via Retrofit converter) | (Retrofit 2.9.0) | Apache-2.0 | https://github.com/google/gson |
| retrofit2-kotlinx-serialization-converter | 1.0.0 | Apache-2.0 | https://github.com/JakeWharton/retrofit2-kotlinx-serialization-converter |
| JNA | 5.14.0 | Apache-2.0 (elected; dual-licensed Apache-2.0 OR LGPL-2.1+) | https://github.com/java-native-access/jna |

JNA is dual-licensed. YamabikoChat uses JNA under **Apache License 2.0**, not LGPL.

Release APKs exclude duplicate `META-INF/AL2.0` and `META-INF/LGPL2.1` files to avoid merge conflicts. License notices for those libraries are provided here and in the in-app open-source licenses screen instead.

## iOS libraries

| Component | Version | SPDX | Source |
| --- | --- | --- | --- |
| GRDB.swift | 7.x (from 7.0.0) | MIT | https://github.com/groue/GRDB.swift |
| Yams | 6.2.2 | MIT | https://github.com/jpsim/Yams |
| ZIPFoundation | 0.9.20 | MIT | https://github.com/weichsel/ZIPFoundation |

### Embedded Python runtime

| Component | Version / pin | License | Source |
| --- | --- | --- | --- |
| CPython / Python-Apple-support | 3.14-b10 | PSF-2.0 and included third-party terms | https://github.com/beeware/Python-Apple-support |
| NumPy | `ec6b2b2626d0fc2b1505f3ffd7905862ebe605f4` | BSD-3-Clause and included third-party terms | https://github.com/numpy/numpy |
| Matplotlib | 3.11.1 | PSF-based Matplotlib license and included third-party terms | https://github.com/matplotlib/matplotlib |
| Pillow | 12.3.0 | HPND and included third-party terms | https://github.com/python-pillow/Pillow |
| contourpy | 1.3.3 | BSD-3-Clause | https://github.com/contourpy/contourpy |
| kiwisolver | 1.5.0 | BSD-3-Clause | https://github.com/nucleic/kiwi |
| cycler | 0.12.1 | BSD-3-Clause | https://github.com/matplotlib/cycler |
| fonttools | 4.63.0 | MIT | https://github.com/fonttools/fonttools |
| packaging | 26.3 | Apache-2.0 OR BSD-2-Clause | https://github.com/pypa/packaging |
| pyparsing | 3.3.2 | MIT | https://github.com/pyparsing/pyparsing |
| python-dateutil | 2.9.0.post0 | Apache-2.0 OR BSD-3-Clause | https://github.com/dateutil/dateutil |
| six | 1.17.0 | MIT | https://github.com/benjaminp/six |
| Noto multilingual fonts | `google/fonts@ec626514f79f831f1ab848a82114a0ce7e2d6372` | OFL-1.1 | https://github.com/google/fonts/tree/ec626514f79f831f1ab848a82114a0ce7e2d6372/ofl |

The package-specific license and attribution files shipped by these wheels are
retained in their bundled `.dist-info` metadata directories.

The Noto font license and copyright notices are bundled in
`legal/NOTO_FONTS_LICENSES.txt` and exposed from the in-app open-source
licenses screen.

## Pi runtime npm packages

The bundled `PiRuntime/bundle/main.js` is produced from the production dependencies in `ios/PiRuntime/package-lock.json`. Those packages are MIT, Apache-2.0, BSD-3-Clause, ISC, BlueOak-1.0.0, or 0BSD. See [third_party/npm-licenses.md](third_party/npm-licenses.md) for package names, versions, and SPDX identifiers.

`esbuild` is used only at build time and is not redistributed in the app.

## License texts

### MIT License

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Individual MIT packages retain their own copyright notices.

### Apache License 2.0

```
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS
```

### ISC License

```
Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```

### BSD 3-Clause License

```
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### 0BSD

```
Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
```

### Blue Oak Model License 1.0.0

```
# Blue Oak Model License

Version 1.0.0

## Purpose

This license gives everyone as much permission to work with
this software as possible, while protecting contributors
from liability.

## Acceptance

In order to receive this license, you must agree to its
rules.  The rules of this license are both obligations
under that agreement and conditions to your license.
You must not do anything with this software that triggers
a rule that you cannot or will not follow.

## Copyright

Each contributor licenses you to do everything with this
software that would otherwise infringe that contributor's
copyright in it.

## Notices

You must ensure that everyone who gets a copy of
any part of this software from you, with or without
changes, also gets the text of this license or a link to
<https://blueoakcouncil.org/license/1.0.0>.

## Excuse

If anyone notifies you in writing that you have not
complied with [Notices](#notices), you can keep your
license by taking all practical steps to comply within 30
days after the notice.  If you do not do so, your license
ends immediately.

## Patent

Each contributor licenses you to do everything with this
software that would otherwise infringe any patent claims
they can license or become able to license.

## Reliability

No contributor can revoke this license.

## No Liability

As far as the law allows, this software comes as is,
without any warranty or condition, and no contributor
will be liable to anyone for any damages related to this
software or this license, under any kind of legal claim.
```

### Node.js / NodeMobile

The complete Node.js license, including third-party components shipped inside Node.js, is in [third_party/nodejs-mobile/LICENSE](third_party/nodejs-mobile/LICENSE).
