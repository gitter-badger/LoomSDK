/*
 * ===========================================================================
 * Loom SDK
 * Copyright 2011, 2012, 2013
 * The Game Engine Company, LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * ===========================================================================
 */

#pragma once

#include "loom/graphics/internal/bgfx/include/bgfx.h"
#include "loom/common/utils/utString.h"
#include "loom/script/native/lsNativeDelegate.h"

namespace GFX
{
typedef int   TextureID;

#define TEXTUREINVALID    -1
#define MAXTEXTURES       4096

// loading textures are marked
#define MARKEDTEXTURE     65534

struct TextureInfo
{
    TextureID                id;

    // todo: format

    int                      width;
    int                      height;

    bool                     reload;

    bgfx::TextureHandle      handle;

    utString                 texturePath;

    LS::NativeDelegate       updateDelegate;

    const LS::NativeDelegate *getUpdateDelegate() const
    {
        return &updateDelegate;
    }

    void                     reset()
    {
        width       = height = 0;
        reload      = false;
        handle.idx  = bgfx::invalidHandle;
        texturePath = "";
    }
};

class Texture
{
    friend class Graphics;
    friend class QuadRenderer;

private:

    static utHashTable<utFastStringHash, TextureID> sTexturePathLookup;

    // simple linear TextureID -> TextureHandle
    static TextureInfo sTextureInfos[MAXTEXTURES];

    static TextureID getAvailableTextureID()
    {
        TextureID id;

        for (id = 0; id < MAXTEXTURES; id++)
        {
            if (sTextureInfos[id].handle.idx == bgfx::invalidHandle)
            {
                break;
            }
        }

        if (id == MAXTEXTURES)
        {
            return TEXTUREINVALID;
        }

        return id;
    }

    static void initialize();

    static void handleAssetNotification(void *payload, const char *name);

public:

    inline static TextureInfo *getTextureInfo(const char *path)
    {
        TextureID *pid = sTexturePathLookup.get(path);

        if (!pid)
        {
            return NULL;
        }

        if (pid)
        {
            return getTextureInfo(*pid);
        }

        return NULL;
    }

    inline static TextureInfo *getTextureInfo(TextureID id)
    {
        if ((id < 0) || (id >= MAXTEXTURES))
        {
            return NULL;
        }

        TextureInfo *tinfo = &sTextureInfos[id];

        if (tinfo->handle.idx == bgfx::invalidHandle)
        {
            return NULL;
        }

        return tinfo;
    }

    static void reset();

    // This method accepts rgba data.
    static TextureInfo *load(uint8_t *data, uint16_t width, uint16_t height, TextureID id = -1);

    static TextureInfo *initFromAssetManager(const char *path);

    static void dispose(TextureID id);

    static void scaleImageOnDisk(const char *outPath, const char *inPath, int maxWidth, int maxHeight, bool preserveAspect);
};
}
