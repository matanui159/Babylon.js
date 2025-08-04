import { Logger } from "core/Misc/logger";
import { Scene } from "core/scene";
import type { Nullable } from "core/types";

import { ClusteredLight } from "./clusteredLight";
import { Light } from "../light";

declare module "core/scene" {
    // eslint-disable-next-line @typescript-eslint/naming-convention
    export interface Scene {
        /** @internal */
        _clusteredLight: Nullable<ClusteredLight>;

        /**
         * Set to true to enable clustered lighting.
         */
        clusteredLighting: boolean;
    }
}

declare module "../light" {
    // eslint-disable-next-line @typescript-eslint/naming-convention
    export interface Light {
        /** @internal */
        _isClustered: boolean;
        /** @internal */
        _updateClusteredFlag(syncMeshes?: boolean): void;
    }
}

Object.defineProperty(Scene.prototype, "clusteredLighting", {
    get: function (this: Scene): boolean {
        return Boolean(this._clusteredLight);
    },
    set: function (this: Scene, enabled: boolean): void {
        let update = false;
        if (!this._clusteredLight && enabled) {
            this._clusteredLight = new ClusteredLight("SceneClusteredLight", [], this);
            if (this._clusteredLight.isSupported) {
                update = true;
            } else {
                Logger.Warn("Clustered lighting is not supported");
                // Cause it to be disposed below
                enabled = false;
            }
        }
        if (this._clusteredLight && !enabled) {
            this._clusteredLight.dispose(true, true);
            this._clusteredLight = null;
            update = true;
        }

        if (update) {
            // Update all lights
            for (const light of this.lights) {
                light._updateClusteredFlag();
            }
        }
    },
    enumerable: true,
    configurable: true,
});

Light.prototype._updateClusteredFlag = function (this: Light, syncMeshes = true): void {
    const scene = this.getScene();
    const isClustered = scene.clusteredLighting && this.isEnabled() && ClusteredLight.IsLightSupported(this);
    if (Boolean(this._isClustered) === isClustered) {
        return;
    }
    this._isClustered = isClustered;

    if (scene._clusteredLight) {
        // Update the clustered light list if needed
        const index = scene._clusteredLight.lights.indexOf(this);
        if (isClustered && index === -1) {
            scene._clusteredLight.addLight(this, false);
        } else if (!isClustered && index !== -1) {
            scene._clusteredLight.removeLight(this, false);
        }
    }

    if (syncMeshes) {
        // Resync meshes
        for (const mesh of scene.meshes) {
            mesh._resyncLightSource(this);
        }
    }
};
