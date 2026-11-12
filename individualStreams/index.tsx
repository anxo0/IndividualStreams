/*
 * IndividualStreams, un plugin para Vencord
 * Copyright (c) 2026 anxo0
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { NavContextMenuPatchCallback } from "@api/ContextMenu";
import ErrorBoundary from "@components/ErrorBoundary";
import definePlugin from "@utils/types";
import { findByPropsLazy, findComponentByCodeLazy, findExportedComponentLazy, findStoreLazy } from "@webpack";
import { ApplicationStreamingStore, FluxDispatcher, Menu, PopoutWindowStore, React, showToast, UserStore } from "@webpack/common";

const ChannelRTCStore = findStoreLazy("ChannelRTCStore");
const VolumeControl = findComponentByCodeLazy("currentVolume:", "sliderClassName:");
const WindowLaunchIconModule = findByPropsLazy("WindowLaunchIcon");
const FullscreenEnterIcon = findExportedComponentLazy("FullscreenEnterIcon");

const PARTICIPANT_TYPE_STREAM = 0;

// El mismo icono de "Abrir en ventana" de Discord, con un 1 dentro
function IndividualIcon(props: any) {
    const icon = WindowLaunchIconModule.WindowLaunchIcon(props);
    const [firstPath] = React.Children.toArray(icon.props.children) as React.ReactElement<any>[];

    return React.cloneElement(icon, undefined, icon.props.children,
        <path
            fill={firstPath.props.fill}
            className={firstPath.props.className}
            d="M12 9.5V18h-2v-5.9l-1.6 1-1-1.7 2.9-1.9z"
        />
    );
}

function openParticipant(channelId: string, participantId: string) {
    // La saca de la cuadrícula principal; Discord la devuelve sola al cerrar la ventana
    FluxDispatcher.dispatch({ type: "CHANNEL_RTC_POPOUT_PARTICIPANT", channelId, participantId });

    // Discord abre una ventana distinta por cada participante
    FluxDispatcher.dispatch({ type: "CALL_TILE_POPOUT_WINDOW_OPEN", channelId, participantId });
}

function openIndividual(ownerId: string) {
    const stream = ApplicationStreamingStore.getActiveStreamForUser(ownerId)
        ?? ApplicationStreamingStore.getAllActiveStreams().find(s => s.ownerId === ownerId);

    const participant = stream && ChannelRTCStore.getStreamParticipants(stream.channelId)
        .find(p => p.stream?.ownerId === ownerId);

    if (!stream || !participant) {
        showToast({ text: "Primero tienes que estar viendo esa transmisión", variant: "critical" });
        return;
    }

    openParticipant(stream.channelId, participant.id);
}

function toggleFullscreen(e: React.MouseEvent) {
    const doc = (e.currentTarget as HTMLElement).ownerDocument;
    if (doc.fullscreenElement) doc.exitFullscreen();
    else doc.getElementById("app-mount")?.requestFullscreen();
}

// Reutiliza el botón de "Abrir en ventana" de Discord cambiándole solo el icono y el texto
const BarButton = ErrorBoundary.wrap(({ PopoutButton, channelId, participantId, ...rest }: any) => (
    <PopoutButton
        {...rest}
        popoutOpen={false}
        onOpenPopout={() => openParticipant(channelId, participantId)}
        onClosePopout={() => { }}
        label="Abrir individual"
        iconComponent={IndividualIcon}
    />
), { noop: true });

const PopoutVolume = ErrorBoundary.wrap(({ channelId, participantId }: { channelId: string; participantId: string; }) => {
    const participant = ChannelRTCStore.getParticipant(channelId, participantId);
    const userId = participant?.user?.id;
    if (participant?.type !== PARTICIPANT_TYPE_STREAM || !userId || userId === UserStore.getCurrentUser()?.id) return null;

    const popoutWindow = PopoutWindowStore.getWindow(`DISCORD_CALL_TILE_POPOUT_${channelId}_${participantId}`);

    return (
        <div
            style={{ display: "flex", alignItems: "center", color: "#fff" }}
            onClick={e => e.stopPropagation()}
            onDoubleClick={e => e.stopPropagation()}
        >
            <VolumeControl userId={userId} context="stream" currentWindow={popoutWindow ?? window} />
        </div>
    );
}, { noop: true });

function addItem(children: Array<React.ReactNode>, ownerId: string) {
    children.push(
        <Menu.MenuSeparator />,
        <Menu.MenuItem
            id="vc-open-individual-stream"
            label="Abrir individual"
            action={() => openIndividual(ownerId)}
        />
    );
}

const streamContextPatch: NavContextMenuPatchCallback = (children, { stream }) => {
    if (stream?.ownerId) addItem(children, stream.ownerId);
};

const userContextPatch: NavContextMenuPatchCallback = (children, { user }) => {
    if (user && ApplicationStreamingStore.getAnyStreamForUser(user.id)) addItem(children, user.id);
};

export default definePlugin({
    name: "IndividualStreams",
    description: "Abre cada transmisión en su propia ventana para repartirlas entre varias pantallas",
    authors: [{ name: "anxo0", id: 423152530235850753n }],
    enabledByDefault: true,

    patches: [
        {
            // Barra de controles de la llamada: botón junto al de "Abrir en ventana"
            find: "renderBottomRight=()=>",
            replacement: {
                match: /\i\?\(0,\i\.jsx\)\((\i\.\i),\{themeable:(\i),popoutOpen:this\.popoutOpen,className:(\i\.\i),/,
                replace: "$self.renderBarButton(this.props,{PopoutButton:$1,themeable:$2,className:$3}),$&"
            }
        },
        {
            // Ventana individual: volumen y pantalla completa junto a los botones que ya trae
            find: '"stay-on-top"',
            replacement: {
                match: /(\i)\.push\(\(0,\i\.jsx\)\(\i,\{channelId:(\i)\.id,participantId:(\i),hideWhenInactive:!1,idle:(\i)\},"stay-on-top"\)\),\i\.push\(\(0,\i\.jsx\)\((\i),\{/,
                replace: "$self.pushPopoutControls($1,{channelId:$2.id,participantId:$3,idle:$4,TileButton:$5}),$&"
            }
        }
    ],

    renderBarButton(props: any, buttonProps: any) {
        try {
            const { channel, selectedParticipant } = props;
            if (!channel || selectedParticipant?.type !== PARTICIPANT_TYPE_STREAM) return null;

            return <BarButton key="vc-individual-stream" {...buttonProps} channelId={channel.id} participantId={selectedParticipant.id} />;
        } catch {
            return null;
        }
    },

    pushPopoutControls(buttons: React.ReactNode[], { channelId, participantId, idle, TileButton }: any) {
        try {
            buttons.push(
                <PopoutVolume key="vc-individual-volume" channelId={channelId} participantId={participantId} />,
                <TileButton
                    key="vc-individual-fullscreen"
                    icon={FullscreenEnterIcon}
                    tooltipText="Pantalla completa"
                    hideWhenInactive={false}
                    idle={idle}
                    onClick={toggleFullscreen}
                />
            );
        } catch { }
    },

    contextMenus: {
        "stream-context": streamContextPatch,
        "user-context": userContextPatch
    }
});
